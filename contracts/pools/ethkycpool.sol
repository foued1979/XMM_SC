// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../interfaces/ikyc.sol";
import "../enums.sol";

contract ETHKYCPool is XMMPool, IKYC {
    modifier isKYCed() {
        require(_isKYCed[msg.sender], "no kyc");
        _;
    }

    // The list of KYCed user
    mapping (address => bool) _isKYCed;

    constructor(address owner, address compensationToken, uint8 poolTokenDecimals, uint8 compensationTokenDecimals, Terms term, uint8 fee, uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio)
    XMMPool(owner, compensationToken, poolTokenDecimals, compensationTokenDecimals, term, fee, penalty, minDeposit, minWithdrawalRatio) { }

    /// @notice Sets the KYC status for a user
    /// @param user The user address
    function updateKYCUserStatus(address user, bool status) external onlyOwner {
        _isKYCed[user] = status;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param leverage The level of leverage (x1, x2, x3, x5, x7 or x10), if leverage is authorized
    function deposit(LongShort longShort, Leverage leverage) external payable isActive isKYCed isLeveragePossible(leverage) hasMinDeposit(uint128(msg.value)) {
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

        // We just write the deposit
        // The fee is charged when fixing is updated
        writeDeposit(msg.sender, _fixings.length - 1, timestamp, longShort, amount, minFee, leverage);
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public override {
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
}