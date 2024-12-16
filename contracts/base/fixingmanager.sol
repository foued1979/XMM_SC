// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./rebatable.sol";
import "./fixingstore.sol";
import "../enums.sol";
import "../interfaces/ifixingmanager.sol";
import "../libraries/utils.sol";
import "../structures/fixing.sol";

abstract contract FixingManager is FixingStore, Rebatable, IFixingManager {
    modifier haveNoFixing {
        require(_fixingDates.length == 0);
        _;
    }

    /**********
     * Events *
     **********/
    event FixingMissed(uint indexed fixingTimestamp);
    event MissedFixingUpdated(uint indexed timestamp, uint updatedTimestamp);
    event UpdateFrequencyChanged(uint indexed timestamp, uint fromFixingDate, uint newFrequency);

    // ---------------------
    // - Public properties -
    // ---------------------
    /// @notice The start date of the XMM Pool
    uint public StartDate;

    // ----------------------
    // - Private properties -
    // ----------------------
    uint internal _currentFixingUpdateInterval;
    uint internal _currentMidFixingInterval;
    uint[] private _changeOfFixingInterval;
    uint private _fixingThreshold;

    // The expiries and accrualYF for the different terms
    uint[7] internal _expiryIntervals;
    uint64[7] private _expiryYearFractions;
    uint64[7] internal _currentAccrualYFs;
    
    uint[] private _missedFixingTimestamps;    

    // The list of fixingIndex0 for which perf has reached 0 during lifetime
    // We use cartography to facilitate lookup
    // The probability to have 1 position with -100% perf is very low; most likely
    // these mapping will not have a significant size
    mapping(uint => bool[]) private _longZeros;
    mapping(uint => bool[]) private _shortZeros;

    // Internal fields to manage long positions
    uint128[7] internal _longNotionalsForNextFixing;
    mapping(uint => int64[]) internal _longRateIndices;
    uint128 public LongPot;

    // Private fields to manage short positions
    uint128[7] internal _shortNotionalsForNextFixing;
    mapping(uint => int64[]) internal _shortRateIndices;
    uint128 public ShortPot;

    uint8 internal _termsLength;

    constructor(address owner, address compensationToken, uint8 compensationTokenDecimals, uint currentFixingUpdateInterval)
     Rebatable(owner, compensationToken, compensationTokenDecimals) {
        _currentFixingUpdateInterval = currentFixingUpdateInterval;
        _currentMidFixingInterval = currentFixingUpdateInterval >> 1;

        _termsLength = 7;

        for (uint8 i = 0; i < _termsLength; i++) {
            (_expiryIntervals[i], _expiryYearFractions[i]) = Utils.getTermInformation(i);
            _currentAccrualYFs[i] = Utils.getAccrualYF(currentFixingUpdateInterval, _expiryIntervals[i]);
        }

        setFixingThreshold();
    }

    /******************
     * Public Methods *
     ******************/
     /// @notice Updates the update interval for the fixings
    function changeUpdateInterval(UpdateIntervals updateInterval) external onlyOwner {
        if (updateInterval == UpdateIntervals.OneMin) _currentFixingUpdateInterval = Utils.ONE_MINUTE_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.TwoMin) _currentFixingUpdateInterval = Utils.TWO_MINUTES_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.ThreeMin) _currentFixingUpdateInterval = Utils.THREE_MINUTES_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.FiveMin) _currentFixingUpdateInterval = Utils.FIVE_MINUTES_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.TenMin) _currentFixingUpdateInterval = Utils.TEN_MINUTES_UPDATE_INTERVAL;
        
        _currentMidFixingInterval = _currentFixingUpdateInterval >> 1;
        StartDate = _fixingDates[_fixingDates.length - 1];

        for (uint8 i = 0; i < _termsLength; i++) {
            _currentAccrualYFs[i] = Utils.getAccrualYF(_currentFixingUpdateInterval, _expiryIntervals[i]);
        }

        setFixingThreshold();
        
        emit UpdateFrequencyChanged(block.timestamp, StartDate + _currentFixingUpdateInterval, _currentFixingUpdateInterval);
    }

    /// @notice Gets the fixings `from` date `to` date
    /// @param from The starting date for the fixing
    /// @param to   The end date for the fixing
    // If from and to do not fall on exact fixing dates, returns false and empty data
    // Otherwise, returns the list of fixing dates and the corresponding fixings
    function getFixings(uint from, uint to) external view onlyOwner returns(bool, uint[] memory, Fixing[] memory) {
        return _getFixings(from, to);
    }
    
    /// @notice Gets the long and short index values
    function getLastRateIndices() external view returns(int64[] memory long, int64[] memory short) {
        uint lastFixingTimestamp = getLastFixingTimestamp();
        return (_longRateIndices[lastFixingTimestamp], _shortRateIndices[lastFixingTimestamp]);
    }

    /// @notice Returns the indices of the missed fixings, if ever.
    ///         If there is no missed fixings, the array is empty
    function getMissedFixings() external view returns(uint[] memory) {
        return _missedFixingTimestamps;
    }

    /// @notice Sets the first fixing and activates the pool
    // From IXMMPool
    function setFirstFixing(uint64 spot, uint64[] memory callPremia_t_1__t, uint64[] memory putPremia_t_1__t) external onlyOwner haveNoFixing {
        uint tentativeStart = getLastFixingTimestamp();
        uint delay = block.timestamp > tentativeStart ? block.timestamp - tentativeStart : tentativeStart - block.timestamp;
        
        // We can update only from 1 minute around the first fixing time
        require(delay <= 60, "Not sync");
        
        StartDate = tentativeStart;
        Fixing memory fixing = Fixing(StartDate, spot, callPremia_t_1__t, putPremia_t_1__t);
        _addFixing(fixing);

        int64[] memory startIndices = new int64[](_termsLength);

        _longRateIndices[tentativeStart] = startIndices;
        _shortRateIndices[tentativeStart] = startIndices;

        IsActivated = true;
    }

    /// @notice Sets the latest fixing for the XMM
    // From IXMMPool
    function setFixing(uint64 spot, uint64[] memory callPremia_t_1__t, uint64[] memory putPremia_t_1__t)
     external onlyOwner returns(bool) {
        Fixing storage lastFixing = _fixings[_fixingDates[_fixingDates.length - 1]];
        uint nextFixingTimestamp = getNextFixingTimestamp();

        if (nextFixingTimestamp == lastFixing.timestamp) {
            // If the update is done within the threshold, we update the fixing
            if (Math.sub(nextFixingTimestamp + _currentFixingUpdateInterval, block.timestamp) <= _fixingThreshold) {
                nextFixingTimestamp += _currentFixingUpdateInterval;
            // Otherwise, we are too early to update the fixing
            } else return false;
        }
        else if (nextFixingTimestamp == lastFixing.timestamp + _currentFixingUpdateInterval) {
            // If the update is done after the threshold, the fixing is missed
            if (Math.sub(block.timestamp, nextFixingTimestamp) > _fixingThreshold) {
                addTemporaryMissingFixings(lastFixing, nextFixingTimestamp + _currentFixingUpdateInterval);
                return false;
            }
        }
        // The last case is when at least 1 fixing have been missed (e.g. due to a technical error)
        // We fill in missing fixings with last know spot value, and we will update the missing fixings later.
        else {
            // If we are threshold minutes before the next update, we adjust the next fixing timestamp
            if (Math.absSub(nextFixingTimestamp + _currentFixingUpdateInterval, block.timestamp) <= _fixingThreshold) nextFixingTimestamp += _currentFixingUpdateInterval;
            // However if we are outside the threshold, above or below the next fixing timestamp, then the fixing is missed
            else if (Math.absSub(block.timestamp, nextFixingTimestamp) > _fixingThreshold) return false;

            // We add temporary fixings for the missed fixings, excluding the last fixing
            // The missed fixings can be manually updated later
            addTemporaryMissingFixings(lastFixing, nextFixingTimestamp);
        }

        Fixing memory fixing = Fixing(nextFixingTimestamp, spot, callPremia_t_1__t, putPremia_t_1__t);
        _addFixing(fixing);

        executeMarginCall(lastFixing.spot);
        
        incorporateNextNotionals();

        return true;
    }

    /// @notice Writes the indices of position which have reached -100% perf
    function addIndexofZeros(uint[][] memory longZeros, uint[][] memory shortZeros) external onlyOwner {
        // We add the new fixingIndex0s which are leading to -100% perf as of fixing date
        // We loop over the different Terms: i = 0 <=> 1D term
        for (uint i = 0; i < _termsLength; i++) {
            uint[] memory longZeros_term_i = longZeros[i];
            uint[] memory shortZeros_term_i = shortZeros[i];
            
            // We change the mapping:
            // For fixingIndex0 date (<-> longZeros_term_i[j] for long), we change term_i to true 
            for (uint j = 0; j < longZeros_term_i.length; j++) _longZeros[longZeros_term_i[j]][i] = true;
            for (uint j = 0; j < shortZeros_term_i.length; j++) _shortZeros[shortZeros_term_i[j]][i] = true;
        }
    }

    /// @notice In case a fixing update has been missed, owner can update the missed past fixings
    ///         To avoid multiple updates or wrong fixing updates, only the missed fixing index can be updated 1 time
    function updateMissedFixing(uint missedFixingTimestamp, uint64 spot, uint64[] memory callPremia_t_1__t, uint64[] memory putPremia_t_1__t) external onlyOwner {
        (bool good, uint missedFixingIndex) = Utils.itemExistsInArray(missedFixingTimestamp, _missedFixingTimestamps);
        require(good, "Bad missed timestamp");

        (uint64 prevFixingSpot, Fixing storage lastFixing) = _getMissedFixingInfo(missedFixingTimestamp);

        // We update the fixing ith the proper market data
        lastFixing.spot = spot;
        lastFixing.callPremia_t_1__t = callPremia_t_1__t;
        lastFixing.putPremia_t_1__t = putPremia_t_1__t;

        // We compute the new interest factor for both long and short side
        // The updateIndex method also proceeds to margin call
        (int64[] memory longRateFactors, int64[] memory shortRateFactors) = computeAccruals(prevFixingSpot, lastFixing);

        transfer(longRateFactors, shortRateFactors);

        // We update all the indices from missedFixingIndex to the last fixing index
        // The update factors are longRateFactor for the long side and shortRateFactor for the short side
        
        
        for (uint j = _fixingDateToIndex[missedFixingTimestamp]; j < _fixingDates.length - 1; j++)
        {
            uint fixingDate = _fixingDates[j];

            // We update the positions by term
            for (uint8 k = 0; k < _termsLength; k++) {
                
                _longRateIndices[fixingDate][k] = Math.addSigned(_longRateIndices[fixingDate][k], longRateFactors[k]);
                _shortRateIndices[fixingDate][k] = Math.addSigned(_shortRateIndices[fixingDate][k], shortRateFactors[k]);
            }
        }

        _missedFixingTimestamps[missedFixingIndex] = _missedFixingTimestamps[_missedFixingTimestamps.length - 1];
        _missedFixingTimestamps.pop();

        emit MissedFixingUpdated(block.timestamp, missedFixingTimestamp);
    }

    /*******************
     * Virtual Methods *
     *******************/
    function incorporateNextNotionals() internal virtual;
    function computeAccruals(uint64 spotAtPeriodStart, Fixing storage lastFixing) internal virtual returns(int64[] memory longRateAccruals, int64[] memory shortRateAccruals);
    function executeMarginCall(uint64 prevSpot) internal virtual;
    function transfer(int64[] memory longRateFactors, int64[] memory shortRateFactors) internal virtual;

    /********************
     * Internal Methods *
     ********************/
    /// @notice Returns whether a position started at fixingIndex0 has reached 0 during position lifetime
    function isZeroPerf(Position storage pos) internal view returns(bool) {
        uint8 T = uint8(pos.term);
        if (pos.longShort == LongShort.Long) { return _longZeros[pos.startDate][T]; }
        return _shortZeros[pos.startDate][T];
    }

    /// @notice Gets the last fixing timestamp
    function getLastFixingTimestamp() internal view returns(uint) {
        return StartDate + uint((block.timestamp - StartDate) / _currentFixingUpdateInterval) * _currentFixingUpdateInterval;
    }

    /// @notice Gets the next fixing timestamp
    function getNextFixingTimestamp() internal view returns(uint) {
        return StartDate + (uint((block.timestamp - StartDate) / _currentFixingUpdateInterval) + 1) * _currentFixingUpdateInterval;
    }

    /// @notice Gets the Position fixing timestamp
    // If user opens a position first half of fixing interval, the position is opened on previous timestamp
    // Otherwise, position is opened on next timestamp
    function getPositionTimestamp() internal view returns(uint, FixingTypes) {
        uint lastFixing = getLastFixingTimestamp();
        if (block.timestamp > lastFixing + _currentMidFixingInterval) return (lastFixing + _currentFixingUpdateInterval, FixingTypes.Next);
        return (lastFixing, FixingTypes.Previous);
    }

    /*******************
     * Private Methods *
     *******************/
     function addTemporaryMissingFixings(Fixing storage lastFixing, uint nextFixingTimestamp) private {
        uint lastFixingTimestamp = lastFixing.timestamp;
        uint numberOfMissedFixings = uint((nextFixingTimestamp - lastFixingTimestamp) / _currentFixingUpdateInterval) - 1;
        uint64[] memory empty = new uint64[](0);

        int64[] memory lastLongRateIndices = _longRateIndices[lastFixingTimestamp];
        int64[] memory lastShortRateIndices = _shortRateIndices[lastFixingTimestamp];

        // No margin call will be executed since spot perf is 0
        for (uint i = 0; i < numberOfMissedFixings; i++) {
            lastFixingTimestamp += _currentFixingUpdateInterval;

            Fixing memory fixing = Fixing(lastFixingTimestamp, lastFixing.spot, empty, empty);
            
            _longRateIndices[lastFixingTimestamp] = lastLongRateIndices;
            _shortRateIndices[lastFixingTimestamp] = lastShortRateIndices;
            _addFixing(fixing);
            _missedFixingTimestamps.push(lastFixingTimestamp);

            emit FixingMissed(lastFixingTimestamp);
        }
    }

    function setFixingThreshold() private {
        // If the update interval is less than or equal to 2 min, the threshold is 15s
        if (_currentFixingUpdateInterval <= Utils.TWO_MINUTES_UPDATE_INTERVAL) _fixingThreshold = 15;
        // If the update interval is equal to 3 min, the threshold is 30s
        else if (_currentFixingUpdateInterval == Utils.THREE_MINUTES_UPDATE_INTERVAL) _fixingThreshold = 30;
        // If the update interval is equal to 5 min, the threshold is 1 min
        else if (_currentFixingUpdateInterval == Utils.FIVE_MINUTES_UPDATE_INTERVAL) _fixingThreshold = 60;
        // Otherwise the threshold is 2 min
        else _fixingThreshold = 120;
    }
}