// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../structures/position.sol";
import "../enums.sol";

library Utils {
    uint internal constant UPDATE_INTERVAL = 14_400;
    uint internal constant MAX_NUMBER_FIXINGS = 4_380;

    uint internal constant ONE_WEEK_TIME_INTERVAL = 604_800;
    uint internal constant TWO_WEEKS_TIME_INTERVAL = 1_209_600;
    uint internal constant THREE_WEEKS_TIME_INTERVAL = 1_814_400;
    uint internal constant ONE_MONTH_TIME_INTERVAL = 2_592_000;
    uint internal constant TWO_MONTHS_TIME_INTERVAL = 5_184_000;
    uint internal constant THREE_MONTHS_TIME_INTERVAL = 7_776_000;
    uint internal constant ONE_YEAR_TIME_INTERVAL = 31_536_000;

    /// @notice Gets the term value
    function toExpiry(uint positionStartDate, Terms term) internal pure returns(uint) {
        if (term == Terms.OneWeek) return positionStartDate + ONE_WEEK_TIME_INTERVAL;
        if (term == Terms.TwoWeeks) return positionStartDate + TWO_WEEKS_TIME_INTERVAL;
        if (term == Terms.ThreeWeeks) return positionStartDate + THREE_WEEKS_TIME_INTERVAL;
        if (term == Terms.OneMonth) return positionStartDate + ONE_MONTH_TIME_INTERVAL;
        if (term == Terms.TwoMonths) return positionStartDate + TWO_MONTHS_TIME_INTERVAL;
        
        return positionStartDate + THREE_MONTHS_TIME_INTERVAL;
    }

    /// @notice Checks if an address is in an array of addresses
    function itemExistsInArray(address item, address[] memory intoArray) internal pure returns(bool) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return true;
        }

        return false;
    }

    /// @notice Gets the start date of an XMM
    function getTimeStamp(uint blockTimestamp) internal pure returns(uint) {
        return uint(blockTimestamp / UPDATE_INTERVAL) * UPDATE_INTERVAL;
    }

    /// @notice Gets the fixing index corresponding to the block timestamp
    function getFixingIndex(uint blockTimestamp, uint startDate) internal pure returns(uint) {
        uint offset = uint(blockTimestamp / UPDATE_INTERVAL) - uint(startDate / UPDATE_INTERVAL);
        return offset - (offset / MAX_NUMBER_FIXINGS) * MAX_NUMBER_FIXINGS;
    }

    /// @notice Reduces the amount of a position
    function reducePosition(Position storage position, uint128 amount) internal returns(LongShort, uint32, uint128, bool) {
        if (amount > position.amount) {
            position.amount = 0;
            return (position.position, position.positionIndex, position.amount, true);
        } else {
            position.amount -= amount;
            return (position.position, position.positionIndex, amount, false);
        }
    }

    function removePositionFromArray(uint32 indexOfItemToRemove, Position[] storage positions) internal {
        if (indexOfItemToRemove == positions.length) {
            positions.pop();
        } else {
            Position storage lastPosition = positions[positions.length - 1];
            lastPosition.positionIndex = indexOfItemToRemove;
            positions[uint(indexOfItemToRemove)] = lastPosition;
        }
    }
}