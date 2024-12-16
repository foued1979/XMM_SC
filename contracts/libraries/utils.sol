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

    uint internal constant ONE_MINUTE_UPDATE_INTERVAL = 60;
    uint internal constant TWO_MINUTES_UPDATE_INTERVAL = 120;
    uint internal constant THREE_MINUTES_UPDATE_INTERVAL = 180;
    uint internal constant FIVE_MINUTES_UPDATE_INTERVAL = 300;
    uint internal constant TEN_MINUTES_UPDATE_INTERVAL = 600;
    //uint internal constant FIFTEEN_MINUTES_UPDATE_INTERVAL = 900;
    //uint internal constant TWENTY_MINUTES_UPDATE_INTERVAL = 1_200;
    //uint internal constant THIRTY_MINUTES_UPDATE_INTERVAL = 1_800;
    //uint internal constant ONE_HOUR_UPDATE_INTERVAL = 3_600;
    //uint internal constant TWO_HOURS_UPDATE_INTERVAL = 7_200;
    //uint internal constant THREE_HOURS_UPDATE_INTERVAL = 10_800;
    //uint internal constant FOUR_HOURS_UPDATE_INTERVAL = 14_400;

    /// @notice Computes option expiry as a year fraction
    function getTermInformation(uint8 term) internal pure returns(uint expiryInterval, uint64 expiryYF) {
        if (term == 0) return (ONE_DAY_TIMESPAN_INTERVAL, ONE_DAY_YF);
        if (term == 1) return (ONE_WEEK_TIMESPAN_INTERVAL, ONE_WEEK_YF);
        if (term == 2) return (TWO_WEEKS_TIMESPAN_INTERVAL, TWO_WEEKS_YF);
        if (term == 3) return (THREE_WEEKS_TIMESPAN_INTERVAL, THREE_WEEKS_YF);
        if (term == 4) return (ONE_MONTH_TIMESPAN_INTERVAL, ONE_MONTH_YF);
        if (term == 5) return (TWO_MONTHS_TIMESPAN_INTERVAL, TWO_MONTHS_YF);

        return (THREE_MONTHS_TIMESPAN_INTERVAL, THREE_MONTHS_YF);
    }

    /// @notice Checks if an address is in an array of addresses, and returns the index
    function itemExistsInArray(address item, address[] memory intoArray) internal pure returns(bool, uint) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return (true, i);
        }

        return (false, 0);
    }

    /// @notice Checks if a uint is in an array of uint, and returns the index
    function itemExistsInArray(uint item, uint[] storage intoArray) internal view returns(bool, uint) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return (true, i);
        }

        return (false, 0);
    }
    
    /// @notice Gets the position pro-rated holding time. If position has been hold for a longer period of time
    //          than initially expected, the pro-rated time is equal to 1
    function getProRata(uint tradeTimestamp, Position storage position, uint positionTimeSpanInterval) internal view returns(uint64) {
        uint holdingPeriod = SafeMath.subOr0(tradeTimestamp, position.startDate);

        if (holdingPeriod > positionTimeSpanInterval) return Math.One_32;
        return uint64((holdingPeriod << 32) / positionTimeSpanInterval);
    }

    /// @notice Returns the accrual period as a year fraction
    function getAccrualYF(uint currentFixingUpdateInterva, uint expiryInterval) internal pure returns(uint64) {
        return Math.div(uint64(currentFixingUpdateInterva) << 32, uint64(expiryInterval) << 32);
    }

    function removePositionFromArray(uint32 indexOfItemToRemove, Position[] storage positions) internal {
        require(indexOfItemToRemove < positions.length, "Bad Index");
        Position storage lastPosition = positions[positions.length - 1];
        lastPosition.positionIndex = indexOfItemToRemove;
        positions[uint(indexOfItemToRemove)] = lastPosition;
        positions.pop();
    }

    function getAccrualDetails(uint64[] storage premia, uint128[] storage positions, uint64 ratio, uint128 totalPosition) internal view
     returns(uint64 perf, uint64[] memory perfRatiosByTerm) {
        perfRatiosByTerm = new uint64[](7);
        if (totalPosition == 0) return (0, perfRatiosByTerm);

        uint160 sum = 0;
        uint160[] memory tmp = new uint160[](7);

        for (uint8 i = 0; i < 7; i++) {
            tmp[i] = Math.multPerf(premia[i], positions[i]);
            sum += tmp[i];
        }

        for (uint8 i = 0; i < 7; i++) {
            perfRatiosByTerm[i] = uint64(tmp[i] / sum);
        }

        perf = Math.mult(ratio, uint64(sum / totalPosition));
    }
}