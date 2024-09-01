// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./math.sol";
import "../structures/position.sol";
import "../enums.sol";

library Utils {
    uint internal constant ONE_DAY_TIMESTAMP_INTERVAL = 86_400;
    uint internal constant ONE_WEEK_TIMESTAMP_INTERVAL = 604_800;
    uint internal constant TWO_WEEKS_TIMESTAMP_INTERVAL = 1_209_600;
    uint internal constant THREE_WEEKS_TIMESTAMP_INTERVAL = 1_814_400;
    uint internal constant ONE_MONTH_TIMESTAMP_INTERVAL = 2_592_000;
    uint internal constant TWO_MONTHS_TIMESTAMP_INTERVAL = 5_184_000;
    uint internal constant THREE_MONTHS_TIMESTAMP_INTERVAL = 7_776_000;
    uint internal constant ONE_YEAR_TIMESTAMP_INTERVAL = 31_536_000;

    int64 internal constant ONE_DAY_YF = 11_767_034;
    int64 private constant ONE_WEEK_YF = 82_369_236;
    int64 private constant TWO_WEEKS_YF = 164_738_472;
    int64 private constant THREE_WEEKS_YF = 247_107_707;
    int64 private constant ONE_MONTH_YF = 353_011_011; // 30 days
    int64 private constant TWO_MONTHS_YF = 706_022_021; // 60 days
    int64 private constant THREE_MONTHS_YF = 1_059_033_032; // 90 days

    uint private constant FIVE_MINUTES_UPDATE_INTERVAL = 300;
    uint private constant TEN_MINUTES_UPDATE_INTERVAL = 600;
    uint private constant FIFTEEN_MINUTES_UPDATE_INTERVAL = 900;
    uint private constant THIRTY_MINUTES_UPDATE_INTERVAL = 1_800;
    uint internal constant ONE_HOUR_UPDATE_INTERVAL = 3_600;
    uint private constant TWO_HOURS_UPDATE_INTERVAL = 7_200;
    uint private constant FOUR_HOURS_UPDATE_INTERVAL = 14_400;

    /// @notice Computes option expiry as a year fraction
    function getTermInformation(Terms term) internal pure returns(uint updateInterval, uint expiryInterval, int64 expiryYF) {
        if (term == Terms.OneDay) return (TEN_MINUTES_UPDATE_INTERVAL, ONE_DAY_TIMESTAMP_INTERVAL, ONE_DAY_YF);
        if (term == Terms.OneWeek) return (FIFTEEN_MINUTES_UPDATE_INTERVAL, ONE_WEEK_TIMESTAMP_INTERVAL, ONE_WEEK_YF);
        if (term == Terms.TwoWeeks) return (THIRTY_MINUTES_UPDATE_INTERVAL, TWO_WEEKS_TIMESTAMP_INTERVAL, TWO_WEEKS_YF);
        if (term == Terms.ThreeWeeks) return (ONE_HOUR_UPDATE_INTERVAL, THREE_WEEKS_TIMESTAMP_INTERVAL, THREE_WEEKS_YF);
        if (term == Terms.OneMonth) return (TWO_HOURS_UPDATE_INTERVAL, ONE_MONTH_TIMESTAMP_INTERVAL, ONE_MONTH_YF);
        if (term == Terms.TwoMonths) return (FOUR_HOURS_UPDATE_INTERVAL, TWO_MONTHS_TIMESTAMP_INTERVAL, TWO_MONTHS_YF);

        return (FOUR_HOURS_UPDATE_INTERVAL, THREE_MONTHS_TIMESTAMP_INTERVAL, THREE_MONTHS_YF);
    }

    /// @notice Checks if an address is in an array of addresses
    function itemExistsInArray(address item, address[] memory intoArray) internal pure returns(bool) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return true;
        }

        return false;
    }

    function getProRata(uint tradeTimestamp, Position storage position, uint positionTerm) internal view returns(int64) {
        int64 holdingPeriod = int64(uint64(tradeTimestamp - position.startDate)) << 32;
        if (holdingPeriod > Math.One_32) return Math.One_32;

        return Math.div(holdingPeriod, int64(uint64(positionTerm)));
    }

    /// @notice Gets the start date of an XMM
    function getTimeStamp(uint blockTimestamp, uint startDate, uint updateInterval) internal pure returns(uint) {
        return startDate + uint((blockTimestamp - startDate) / updateInterval) * updateInterval;
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