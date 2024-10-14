// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../enums.sol";

contract ETHPool is XMMPool {

    constructor(address owner, address compensationToken, uint8 poolTokenDecimals, uint8 compensationTokenDecimals, Terms term, uint8 fee, uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio)
    XMMPool(owner, compensationToken, poolTokenDecimals, compensationTokenDecimals, term, fee, penalty, minDeposit, minWithdrawalRatio) { }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param leverage The level of leverage (x1, x2, x3, x5, x7 or x10), if leverage is authorized
    function deposit(LongShort longShort, Leverage leverage) external payable isActive isLeveragePossible(leverage) hasMinDeposit(uint128(msg.value)) {
        // Sanity check
        require(msg.value >> 128 == 0, "Deposit overflow");
        uint128 amount = uint128(msg.value);

        uint timestamp = Utils.getTimeStamp(block.timestamp, _fixings[_fixings.length - 1].timestamp, _currentFixingUpdateInterval);
        uint128 minFee = getMinimumFee(msg.sender, timestamp, timestamp + _expiryInterval, amount);
        // The deposit can only be an increase in position
        // -> hence, we remove the minFee from the deposit
        amount = SafeMath.sub128(amount, minFee);

        address payable receiver = payable(Owner);
        receiver.transfer(uint256(minFee));

        writeDeposit(msg.sender, _fixings.length - 1, timestamp, longShort, amount, minFee, leverage);
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public override {
        if (_positions[msg.sender].length > positionIndex) {
            Position storage position = _positions[msg.sender][positionIndex];

            if (amount > position.amount) amount = position.amount;
            uint128 penalty;
            uint128 fee = getPositionFee(block.timestamp, position.startDate, position.expiry, amount, position.minFeePaid);

            // If position is offset before expected term, a penalty applies
            if (position.startDate > block.timestamp || block.timestamp < position.expiry) {
                // This penalty is the for the pool and will remain in pool liquidity
                penalty = applyPenalty(amount);
            }

            int64 rate = getRate(position.longShort, position.leverage, position.fixingIndex0);
            uint128 compensationAmt = 0;

            // If rate is positive, only a pro-rata interest is paid
            // If rate is negative, msg.sender shall pay the full amount due
            if (rate > 0) {
                uint64 proRata = Utils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _currentFixingUpdateInterval), position, _expiryInterval);
                rate = Math.multSigned(int64(proRata), rate);
            }
            else if (isCompensable(position.longShort)) {
                compensationAmt = getCompensationAmount(position.amount, rate, _poolTokenDecimals);
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

            // We remove the penalty and fee
            uint128 totalTransfer = SafeMath.sub128(amount, penalty);
            totalTransfer = SafeMath.sub128(totalTransfer, fee);
            
            // We charge or we pay the interest
            if (rate < 0) totalTransfer = SafeMath.subOr0_128(totalTransfer, uint128(-interest));
            else totalTransfer = SafeMath.add128(totalTransfer, uint128(interest));

            address payable receiver = payable(msg.sender);
            receiver.transfer(uint256(totalTransfer));

            if (fee > 0) {
                address payable owner = payable(Owner);
                owner.transfer(uint256(fee));
            }
            
            if (compensationAmt != 0) CompensationToken.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, uint256(compensationAmt)));
            emit PositionReduced(msg.sender, block.timestamp, totalTransfer);
        }
    }

    function transferFee(uint128 totalShortPosition, uint128 totalLongPosition) internal override returns(uint128 feeShort, uint128 feeLong) {
        address payable receiver = payable(Owner);

        feeShort = uint128((uint136(totalShortPosition) * Fee * _currentAccrualYF / (1_000_000 * Utils.ONE_DAY_YF)));
        receiver.transfer(uint256(feeShort));

        feeLong = uint128((uint136(totalLongPosition) * Fee * _currentAccrualYF / (1_000_000 * Utils.ONE_DAY_YF)));
        receiver.transfer(uint256(feeLong));

        _accumulatedFee = SafeMath.add128(_accumulatedFee, feeShort);
        _accumulatedFee = SafeMath.add128(_accumulatedFee, feeLong);
    }
}