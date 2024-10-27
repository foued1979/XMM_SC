// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../libraries/safemath.sol";
import "../libraries/utils.sol";
import "../enums.sol";

contract CoinPool is XMMPool {
    /// @notice The token which managed by the XMM
    address public Token;

    /// @param minWithdrawalRatio   The ratio that will get the minimum withdrawal amount, where MinWithdrawalAmt = minDeposit * minWithdrawalRatio
    constructor(address token, address owner, address compensationToken, uint8 poolTokenDecimals, uint8 compensationTokenDecimals, Terms term, uint8 fee,
     uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio)
    XMMPool(owner, compensationToken, poolTokenDecimals, compensationTokenDecimals, term, fee, penalty, minDeposit, minWithdrawalRatio) {
        Token = token;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param amount The amount to be deposited
    /// @param leverage The level of leverage (x1, x2, x3, x5, x7 or x10), if leverage is authorized
    function deposit(LongShort longShort, uint128 amount, Leverage leverage) external isActive isLeveragePossible(leverage) hasMinDeposit(amount) {
        (bool success, bytes memory res) = Token.call(abi.encodeWithSelector(IERC20.balanceOf.selector, msg.sender));
        require(success, "Call err");

        uint256 balance = abi.decode(res, (uint256));
        require(balance >= amount, "Insufficient balance");

        (success, res) = Token.call(abi.encodeWithSelector(IERC20.allowance.selector, msg.sender, address(this)));

        if (success) {
            uint256 allowance = abi.decode(res, (uint256));
            require(allowance >= amount, "Insufficient allowance");

            (success, res) = Token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(this), uint256(amount)));

            if (success && abi.decode(res, (bool))) {
                uint timestamp = Utils.getTimeStamp(block.timestamp, _fixings[_fixings.length - 1].timestamp, _currentFixingUpdateInterval);
                uint128 minFee = getMinimumFee(msg.sender, timestamp, timestamp + _expiryInterval, amount);
                // The deposit can only be an increase in position
                // -> hence, we remove the minFee from the deposit
                amount = SafeMath.sub128(amount, minFee);

                Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, minFee));

                // We just write the deposit
                // The fee is charged when fixing is updated
                writeDeposit(msg.sender, _fixings.length - 1, timestamp, longShort, amount, minFee, leverage);
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
            
            // If the position reached -100% perf during its lifetime
            // we just delete the position.
            if (isZeroPerf(position.fixingIndex0, position.longShort)) {
                Utils.removePositionFromArray(positionIndex, _positions[msg.sender]);
                return;
            }

            if (amount > position.amount) amount = position.amount;
            uint128 penalty;
            uint128 fee = getPositionFee(msg.sender, block.timestamp, position.startDate, position.expiry, amount, position.minFeePaid);

            // If position is offset before expected term, a penalty applies
            if (position.startDate > block.timestamp || block.timestamp < position.expiry) {
                // This penalty is the for the pool and will remain in pool liquidity
                penalty = applyPenalty(amount);
            }

            // Via checkPosition, we check the prorated rate if user offsets the position before the term.
            // We also check if the position was pending for the next fixing, to adjust the pending notionals
            // not the live positions.
            (int64 rate, uint128 compensationAmt) = checkPosition(position, amount, getRate(position.longShort, position.leverage, position.fixingIndex0));

            // If amount equals the position amount, we remove the position from user's positions
            if (position.amount <= amount) Utils.removePositionFromArray(positionIndex, _positions[msg.sender]);

            // Interest is computed on the whole amount
            int128 interest = int128((int160(uint160(amount)) * rate) >> 32);

            // We remove the penalty
            // Fee is removed only if user has enough cash at offset
            uint128 totalTransfer = SafeMath.sub128(amount, penalty);

            // We charge or we pay the interest
            if (rate < 0) totalTransfer = SafeMath.subOr0_128(totalTransfer, uint128(-interest));
            else totalTransfer = SafeMath.add128(totalTransfer, uint128(interest));

            // If a user has lost all is money, we cannot charge a fee
            if (totalTransfer == 0) {
                fee = 0;
            }
            else {
                if (totalTransfer <= fee) {
                    fee = totalTransfer;
                    totalTransfer = 0;
                } else {
                    totalTransfer = SafeMath.sub128(totalTransfer, fee);
                }
            }

            (bool success, ) = Token.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, uint256(totalTransfer)));

            if (success) {
                if (fee > 0) Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, uint256(fee)));
                if (compensationAmt != 0) CompensationToken.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, uint256(compensationAmt)));
                emit PositionReduced(msg.sender, block.timestamp, totalTransfer);
            }
        }
    }

    function transferFee(uint128 totalShortPosition, uint128 totalLongPosition) internal override returns(uint128 feeShort, uint128 feeLong) {
        feeShort = uint128((uint136(totalShortPosition) * Fee * _currentAccrualYF / (1_000_000 * Utils.ONE_DAY_YF)));
        Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, uint256(feeShort)));

        feeLong = uint128((uint136(totalLongPosition) * Fee * _currentAccrualYF / (1_000_000 * Utils.ONE_DAY_YF)));
        Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, uint256(feeLong)));

        _accumulatedFee = SafeMath.add128(_accumulatedFee, feeShort);
        _accumulatedFee = SafeMath.add128(_accumulatedFee, feeLong);
    }
}