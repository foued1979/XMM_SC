// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../enums.sol";

contract CoinPool is XMMPool {
    /// @notice The token which managed by the XMM
    address public Token;

    constructor(address token, address owner, uint8 decimals, Terms term, uint8 fee, uint64 minDeposit) XMMPool(owner, decimals, term, fee, mindeposit) {
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
                writeDeposit(msg.sender, Fixings.length - 1, longShort, amount, leverage);
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

            if (position.startDate > block.timestamp || block.timestamp < position.expiry) amount = applyPenalty(amount);

            (LongShort ls, uint32 index, uint128 finalAmount, bool toDelete) = Utils.reducePosition(position, amount);

            int64 proRata = sssUtils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _fixingUpdateInterval), position, _expiryInterval);
            int64 rate = getRate(ls, proRata, position.index0);

            if (ls == LongShort.Long) {
                TotalLongPositions = SafeMath.SafeSub128(TotalLongPositions, finalAmount);
            } else {
                TotalShortPositions = SafeMath.SafeSub128(TotalShortPositions, finalAmount);
            }

            getRatios();

            if (toDelete) Utils.removePositionFromArray(index, _positions[msg.sender]);

            finalAmount = uint128(int128(((int256(int128(finalAmount)) << 32) * rate) >> 32));
            (bool success, ) = Token.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, finalAmount));

            if (success) emit PositionReduced(msg.sender, block.timestamp, finalAmount);
        }
    }
}