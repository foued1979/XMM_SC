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

    constructor(address owner, uint8 decimals, Terms term, uint8 fee, uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio)
    XMMPool(owner, decimals, term, fee, penalty, minDeposit, minWithdrawalRatio) { }

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

        uint128 fee = uint128((uint136(amount) * Fee) / 1_000_000);
        uint128 netAmt = SafeMath.sub128(amount, fee);

        writeDeposit(msg.sender, _fixings.length - 1, longShort, netAmt, leverage);

        address payable receiver = payable(Owner);
        receiver.transfer(uint256(fee));
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

            address payable receiver = payable(msg.sender);
            receiver.transfer(uint256(totalTransfer));
            emit PositionReduced(msg.sender, block.timestamp, totalTransfer);
        }
    }
}