// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./math.sol";
import "./safemath.sol";
import "../structures/position.sol";
import "../enums.sol";

library Utils {
    uint internal constant ONE_DAY_TIMESPAN_INTERVAL = 86_400;
    uint internal constant ONE_WEEK_TIMESPAN_INTERVAL = 604_800;
    uint internal constant TWO_WEEKS_TIMESPAN_INTERVAL = 1_209_600;
    uint internal constant THREE_WEEKS_TIMESPAN_INTERVAL = 1_814_400;
    uint internal constant ONE_MONTH_TIMESPAN_INTERVAL = 2_592_000;
    uint internal constant TWO_MONTHS_TIMESPAN_INTERVAL = 5_184_000;
    uint internal constant THREE_MONTHS_TIMESPAN_INTERVAL = 7_776_000;
    uint internal constant ONE_YEAR_TIMESPAN_INTERVAL = 31_536_000;

    uint64 internal constant ONE_DAY_YF = 11_767_034;
    uint64 private constant ONE_WEEK_YF = 82_369_236;
    uint64 private constant TWO_WEEKS_YF = 164_738_472;
    uint64 private constant THREE_WEEKS_YF = 247_107_707;
    uint64 private constant ONE_MONTH_YF = 353_011_011; // 30 days
    uint64 private constant TWO_MONTHS_YF = 706_022_021; // 60 days
    uint64 private constant THREE_MONTHS_YF = 1_059_033_032; // 90 days

    uint internal constant FIVE_MINUTES_UPDATE_INTERVAL = 300;
    uint private constant TEN_MINUTES_UPDATE_INTERVAL = 600;
    uint internal constant FIFTEEN_MINUTES_UPDATE_INTERVAL = 900;
    uint private constant THIRTY_MINUTES_UPDATE_INTERVAL = 1_800;
    uint internal constant ONE_HOUR_UPDATE_INTERVAL = 3_600;
    uint private constant TWO_HOURS_UPDATE_INTERVAL = 7_200;
    uint private constant FOUR_HOURS_UPDATE_INTERVAL = 14_400;

    int64 private constant ONE_TIME_LEV = 0x100000000;
    int64 private constant TWO_TIME_LEV = 0x200000000;
    int64 private constant THREE_TIME_LEV = 0x300000000;
    int64 private constant FIVE_TIME_LEV = 0x500000000;
    int64 private constant SEVEN_TIME_LEV = 0x700000000;
    int64 private constant TEN_TIME_LEV = 0xA00000000;

    /// @notice Computes option expiry as a year fraction
    function getTermInformation(Terms term) internal pure returns(uint updateInterval, uint expiryInterval, uint64 expiryYF) {
        if (term == Terms.OneDay) return (TEN_MINUTES_UPDATE_INTERVAL, ONE_DAY_TIMESPAN_INTERVAL, ONE_DAY_YF);
        if (term == Terms.OneWeek) return (FIFTEEN_MINUTES_UPDATE_INTERVAL, ONE_WEEK_TIMESPAN_INTERVAL, ONE_WEEK_YF);
        if (term == Terms.TwoWeeks) return (THIRTY_MINUTES_UPDATE_INTERVAL, TWO_WEEKS_TIMESPAN_INTERVAL, TWO_WEEKS_YF);
        if (term == Terms.ThreeWeeks) return (ONE_HOUR_UPDATE_INTERVAL, THREE_WEEKS_TIMESPAN_INTERVAL, THREE_WEEKS_YF);
        if (term == Terms.OneMonth) return (TWO_HOURS_UPDATE_INTERVAL, ONE_MONTH_TIMESPAN_INTERVAL, ONE_MONTH_YF);
        if (term == Terms.TwoMonths) return (FOUR_HOURS_UPDATE_INTERVAL, TWO_MONTHS_TIMESPAN_INTERVAL, TWO_MONTHS_YF);

        return (FOUR_HOURS_UPDATE_INTERVAL, THREE_MONTHS_TIMESPAN_INTERVAL, THREE_MONTHS_YF);
    }

    /// @notice Checks if an address is in an array of addresses
    function itemExistsInArray(address item, address[] memory intoArray) internal pure returns(bool) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return true;
        }

        return false;
    }

    /// @notice Checks if an address is in an array of addresses
    function itemExistsInArray(uint item, uint[] storage intoArray) internal view returns(bool) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return true;
        }

        return false;
    }

    /// @notice Returns the leverage factor as int64
    function getLeverageFactor(uint8 lev) internal pure returns(int64) {
        if (lev == 0) return ONE_TIME_LEV;
        if (lev == 1) return TWO_TIME_LEV;
        if (lev == 2) return THREE_TIME_LEV;
        if (lev == 3) return FIVE_TIME_LEV;
        if (lev == 4) return SEVEN_TIME_LEV;
        if (lev == 5) return TEN_TIME_LEV;
    }

    // Function name has been changed to make sure that positionTerm is properly defined when function is called
    // positionTerm corresponds to the timestamp of the position end date.
    function getProRata(uint tradeTimestamp, Position storage position, uint positionTimeSpanInterval) internal view returns(uint64) {
        uint holdingPeriod = SafeMath.sub(tradeTimestamp, position.startDate);

        if (holdingPeriod > positionTimeSpanInterval) return Math.One_32;
        return uint64((holdingPeriod << 32) / positionTimeSpanInterval);
    }

    /// @notice Gets the start date of an XMM
    function getTimeStamp(uint blockTimestamp, uint startDate, uint updateInterval) internal pure returns(uint) {
        return startDate + uint((blockTimestamp - startDate) / updateInterval) * updateInterval;
    }

    function removePositionFromArray(uint32 indexOfItemToRemove, Position[] storage positions) internal {
        require(indexOfItemToRemove < positions.length, "Bad Index");
        Position storage lastPosition = positions[positions.length - 1];
            lastPosition.positionIndex = indexOfItemToRemove;
            positions[uint(indexOfItemToRemove)] = lastPosition;
    }
}