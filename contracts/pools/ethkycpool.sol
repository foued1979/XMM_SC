// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../interfaces/ikyc.sol";
import "../enums.sol";

contract ETHKYCPool is XMMPool. IKYC {
    modifier isKYCed() {
        require(_isKYCed[msg.sender], "no kyc");
        _;
    }

    // The list of KYCed user
    mapping (address => bool) _isKYCed;

    constructor(address owner, uint8 decimals, Terms term, uint64 minDeposit) XMMPool(owner, decimals, term, mindeposit) { }

    /// @notice Sets the KYC status for a user
    /// @param user The user address
    function updateKYCUserStatus(address user, bool status) external onlyOwner {
        _isKYCed[user] = status;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    function deposit(LongShort longShort) external payable isActive isKYCed {
        if (success && abi.decode(res, (bool))) {
            uint lastFixingIndex = Fixings.length;
            uint32 positionIndex = uint32(_positions[msg.sender].length);
            uint timestamp = Fixings[lastFixingIndex].timestamp;
            uint128 amount = uint128(msg.value);

            // If position is opened after mid update interval, the next fixing is used
            if (block.timestamp > timestamp + _midFixingInterval) {
                timestamp += _fixingUpdateInterval;
                lastFixingIndex++;
            }

            Position memory position = Position(positionIndex, longShort, lastFixingIndex, timestamp, timestamp + _expiryInterval, amount);
            _positions[msg.sender].push(position);
                
            if (longShort == LongShort.Long) {
                TotalLongPositions = SafeMath.SafeAdd128(TotalLongPositions, amount);
            } else {
                TotalShortPositions = SafeMath.SafeAdd128(TotalShortPositions, amount);
            }

            getRatios();

            emit Deposit(msg.sender, block.timestamp, position);
        }
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public override {
        if (_positions[msg.sender].length > positionIndex) {
            Position storage position = _positions[msg.sender][positionIndex];
            if (position.startDate > block.timestamp) Penalty
            else if (block.timestamp < position.expiry) Another Penalty

            (LongShort ls, uint32 index, uint128 finalAmount, bool toDelete) = Utils.reducePosition(position, amount);

            int64 proRata = Utils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _fixingUpdateInterval), position, _expiryInterval);
            int64 rate = getRate(ls, proRata, position.index0);

            if (ls == LongShort.Long) {
                TotalLongPositions = SafeMath.SafeSub128(TotalLongPositions, finalAmount);
            } else {
                TotalShortPositions = SafeMath.SafeSub128(TotalShortPositions, finalAmount);
            }

            getRatios();

            if (toDelete) Utils.removePositionFromArray(index, _positions[msg.sender]);

            finalAmount = uint128(int128(((int256(int128(finalAmount)) << 32) * rate) >> 32));
            address payable receiver = payable(msg.sender);
            receiver.transfer(finalAmount);

            if (success) emit PositionReduced(msg.sender, block.timestamp, finalAmount);
        }
    }
}