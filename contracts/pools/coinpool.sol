// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../libraries/safemath.sol";
import "../enums.sol";

contract CoinPool is XMMPool {
    /// @notice The token which managed by the XMM
    address public Token;

    constructor(address token, address owner, uint8 decimals, Terms term, uint8 fee, uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio)
    XMMPool(owner, decimals, term, fee, penalty, minDeposit, minWithdrawalRatio) {
        Token = token;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param amount The amount to be deposited
    function deposit(LongShort longShort, uint128 amount, Leverage leverage) external isActive isLeveragePossible(leverage) hasMinDeposit(amount) {
        (bool success, bytes memory res) = Token.call(abi.encodeWithSelector(IERC20.balanceOf.selector, msg.sender));
        require(success, "Call err");

        uint256 balance = abi.decode(res, (uint256));
        require(balance >= amount, "Insufficient balance");

        (success, res) = Token.call(abi.encodeWithSelector(IERC20.allowance.selector, msg.sender, address(this)));

        if (success) {
            uint256 allowance = abi.decode(res, (uint256));

            require(allowance >= amount, "Insufficient allowance");

            uint128 fee = uint128((uint136(amount) * Fee) / 1_000_000);
            amount -= fee;

            (success, res) = Token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(this), uint256(amount)));

            if (success && abi.decode(res, (bool))) {
                writeDeposit(msg.sender, _fixings.length - 1, longShort, amount, leverage);
                (success, res) = Token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(Owner), uint256(fee)));
            }
        }
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public override hasMinWithdrawal(amount) {
        if (_positions[msg.sender].length > positionIndex) {
            Position storage position = _positions[msg.sender][positionIndex];

            if (amount > position.amount) amount = position.amount;
            uint128 penalty;

            // If position is offset before expected term, a penalty applies
            // The penalty amount will remain in pool liquidity
            if (position.startDate > block.timestamp || block.timestamp < position.expiry) penalty = applyPenalty(amount);

            int64 rate = getRate(position.longShort, position.leverage, position.fixingIndex0);

            // If rate is positive, only a pro-rata interest is paid
            // If rate is negative, msg.sender shall pay the full amount due
            if (rate > 0) {
                uint64 proRata = Utils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _fixingUpdateInterval), position, _expiryInterval);
                rate = Math.multSigned(int64(proRata), rate);
            }            

            if (position.longShort == LongShort.Long) {
                TotalLongPositions[uint8(position.leverage)] = SafeMath.sub128(TotalLongPositions[uint8(position.leverage)], amount);
            } else {
                TotalShortPositions[uint8(position.leverage)] = SafeMath.sub128(TotalShortPositions[uint8(position.leverage)], amount);
            }

            setRatios();

            if (position.amount <= amount) Utils.removePositionFromArray(positionIndex, _positions[msg.sender]);

            // Interest is computed on the whole amount
            int128 interest = int128((int160(uint160(amount)) * rate) >> 32);
            // We remove the penalty
            uint128 totalTransfer = SafeMath.sub128(amount, penalty);
            // We charge or we pay the interest
            if (rate < 0) totalTransfer = SafeMath.subOr0_128(totalTransfer, uint128(-interest));
            else totalTransfer = SafeMath.add128(totalTransfer, uint128(interest));

            (bool success, ) = Token.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, uint256(totalTransfer)));

            if (success) emit PositionReduced(msg.sender, block.timestamp, totalTransfer);
        }
    }
}