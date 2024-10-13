// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./compensable.sol";
import "../enums.sol";
import "../interfaces/ifixingmanager.sol";
import "../libraries/utils.sol";
import "../structures/fixing.sol";

abstract contract FixingManager is Compensable, IFixingManager {
    /**********
     * Events *
     **********/
    event FixingMissed(uint indexed fixingTimestamp, uint fixingIndex);
    event MissedFixingUpdated(uint indexed timestamp, uint fixingIndex);
    event UpdateFrequencyChanged(uint indexed timestamp, uint fixingIndex, uint newFrequency);

    // ---------------------
    // - Public properties -
    // ---------------------
    /// @notice The start date of the XMM
    uint public StartDate;

    /// @notice The Term of the XMM
    Terms public Term;

    // ----------------------
    // - Private properties -
    // ----------------------
    uint internal _currentFixingUpdateInterval;
    uint internal _currentMidFixingInterval;
    uint64 internal _currentAccrualYF;

    uint internal _expiryInterval;
    uint64 private _expiryYearFraction;
    
    uint[] private _missedFixingsIndices;

    // The list of fixings
    Fixing[] internal _fixings;

    // Private fields to manage long positions
    mapping(uint8 => uint64) internal _longRatios;
    mapping(uint8 => int64[]) internal _longRateIndices;

    // Private fields to manage short positions
    mapping(uint8 => uint64) internal _shortRatios;
    mapping(uint8 => int64[]) internal _shortRateIndices;

    constructor(address owner, address compensationToken, uint8 compensationTokenDecimals, Terms term) Compensable(owner, compensationToken, compensationTokenDecimals) {
        Term = term;
        init(term);
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
        else if (updateInterval == UpdateIntervals.FifteenMin) _currentFixingUpdateInterval = Utils.FIFTEEN_MINUTES_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.TwentyMin) _currentFixingUpdateInterval = Utils.TWENTY_MINUTES_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.ThirtyMin) _currentFixingUpdateInterval = Utils.THIRTY_MINUTES_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.OneH) _currentFixingUpdateInterval = Utils.ONE_HOUR_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.TwoH) _currentFixingUpdateInterval = Utils.TWO_HOURS_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.ThreeH) _currentFixingUpdateInterval = Utils.THREE_HOURS_UPDATE_INTERVAL;
        else if (updateInterval == UpdateIntervals.FourH) _currentFixingUpdateInterval = Utils.FOUR_HOURS_UPDATE_INTERVAL;
        
        _currentMidFixingInterval = _currentFixingUpdateInterval >> 1;
        _currentAccrualYF = Utils.getAccrualYF(_currentFixingUpdateInterval, _expiryInterval);

        emit UpdateFrequencyChanged(block.timestamp, _fixings.length, _currentFixingUpdateInterval);
    }

    /// @notice Gets the fixings
    function getFixings() external view onlyOwner returns(Fixing[] memory) {
        return _fixings;
    }

    /// @notice Gets the fixings `from` index `to` index
    function getFixingsFromTo(uint from, uint to) external view onlyOwner returns(Fixing[] memory) {
        if (to + 1 > _fixings.length) to = _fixings.length - 1;

        Fixing[] memory res = new Fixing[](to - from + 1);
        for (uint i = from; i <= to; i++) res[i - from] = _fixings[i];
        return res;
    }

    /// @notice Gets the total long and short positions for a given leverage factor
    function getLastIndices(Leverage leverage) external view returns(int64 long, int64 short) {
        return (_longRateIndices[uint8(leverage)][_fixings.length - 1], _shortRateIndices[uint8(leverage)][_fixings.length - 1]);
    }

    /// @notice Returns the indices of the missed fixings, if ever.
    ///         If there is no missed fixings, the array is empty
    function getMissedFixings() external view returns(uint[] memory) {
        return _missedFixingsIndices;
    }

    /// @notice Sets the first fixing and activates the pool
    // From IXMMPool
    function setFirstFixing(uint64 spot, uint64 strike, uint64 volatility, uint64 optionPremium) external onlyOwner {
        if (_fixings.length > 0) return;

        // The start date is the 1st timestamp
        StartDate = Utils.getTimeStamp(block.timestamp, 0, _currentFixingUpdateInterval);
        
        // We can update only from 5 minutes before the first fixing time
        require(block.timestamp - StartDate <= 300, "Not sync");
        
        Fixing memory fixing = Fixing(StartDate, spot, strike, volatility, optionPremium);
        _fixings.push(fixing);

        IsActivated = true;
    }

    /// @notice Sets the latest fixing for the XMM
    // From IXMMPool
    function setFixing(uint64 spot, uint64 strike, uint64 volatility, uint64 optionPremium) external onlyOwner returns(bool) {
        Fixing storage lastFixing = _fixings[_fixings.length - 1];
        uint nextFixingTimestamp = Utils.getTimeStamp(block.timestamp, lastFixing.timestamp, _currentFixingUpdateInterval);

        uint threshold = 0;
        // If the update interval is less than or equal to 2 min, the threshold is 15s
        if (_currentFixingUpdateInterval <= Utils.TWO_MINUTES_UPDATE_INTERVAL) threshold = 15;
        // If the update interval is equal to 3 min, the threshold is 30s
        else if (_currentFixingUpdateInterval == Utils.THREE_MINUTES_UPDATE_INTERVAL) threshold = 30;
        // If the update interval is equal to 5 min, the threshold is 1 min
        else if (_currentFixingUpdateInterval == Utils.FIVE_MINUTES_UPDATE_INTERVAL) threshold = 60;
        // Else if update interval is less than or equal to 15 min, the threshold is 2 min
        else if (_currentFixingUpdateInterval <= Utils.FIFTEEN_MINUTES_UPDATE_INTERVAL) threshold = 120;
        // Otherwise the threshold is 3 min
        else threshold = 180;
        
        if (nextFixingTimestamp == lastFixing.timestamp) {
            // If the update is done within the threshold, we update the fixing
            if (Math.sub(nextFixingTimestamp + _currentFixingUpdateInterval, block.timestamp) <= threshold) {
                nextFixingTimestamp += _currentFixingUpdateInterval;
            // Otherwise, we are too early to update the fixing
            } else return false;
        }
        else if (nextFixingTimestamp == lastFixing.timestamp + _currentFixingUpdateInterval) {
            // If the update is done after the threshold, the fixing is missed
            if (Math.sub(block.timestamp, nextFixingTimestamp) > threshold) return false;
        }
        // However, if at least one fixings has been missed (e.g. due to a technical error), we fill in missing fixings
        // with last know spot value, and we will update the missing fixings later.
        else {
            // If we are threshold minutes before the next update, we adjust the next fixing timestamp
            if (Math.absSub(nextFixingTimestamp + _currentFixingUpdateInterval, block.timestamp) <= threshold) nextFixingTimestamp += _currentFixingUpdateInterval;
            // However if we are outside the threshold, above or below the next fixing timestamp, then the fixing is missed
            else if (Math.absSub(block.timestamp, nextFixingTimestamp) > threshold) return false;

            // We add temporary fixings for the missed fixings, excluding the last fixing
            // The missed fixings can be manually updated later
            addTemporaryMissingFixings(lastFixing.spot, lastFixing.timestamp, nextFixingTimestamp);
        }

        Fixing memory fixing = Fixing(nextFixingTimestamp, spot, strike, volatility, optionPremium);
        executeMarginCall(lastFixing.spot, fixing);
        
        _fixings.push(fixing);
        return true;
    }

    /// @notice In case a fixing update has been missed, owner can update the missed past fixings
    ///         To avoid multiple updates or wrong fixing updates, only the missed fixing index can be updated 1 time
    function updateMissedFixing(uint missedFixingIndex, uint64 spot, uint64 strike, uint64 volatility, uint64 optionPremium) external onlyOwner {
        require(Utils.itemExistsInArray(missedFixingIndex, _missedFixingsIndices), "Bad index");

        Fixing storage prevFixing = _fixings[missedFixingIndex - 1];
        Fixing storage fixing = _fixings[missedFixingIndex];

        // We update the fixing ith the proper market data
        fixing.spot = spot;
        fixing.strike = strike;
        fixing.volatility = volatility;
        fixing.premium = optionPremium;

        // We compute the new interest factor for both long and short side
        // The updateIndex method also proceeds to margin call
        (int64[] memory longRateFactors, int64[] memory shortRateFactors) = computeFactors(prevFixing.spot, fixing.spot, optionPremium);

        transfer(longRateFactors, shortRateFactors);

        // We update all the indices from missedFixingIndex to the last fixing index
        // The update factors are longRateFactor for the long side and shortRateFactor for the short side
        for (uint j = missedFixingIndex; j < _fixings.length; j++)
        {
            for (uint8 k = 0; k < 6; k++) {
                _longRateIndices[k][j] = Math.addSigned(_longRateIndices[k][j - 1], longRateFactors[k]);
                _shortRateIndices[k][j] = Math.addSigned(_shortRateIndices[k][j - 1], shortRateFactors[k]);
            }
        }

        _missedFixingsIndices[missedFixingIndex] = _missedFixingsIndices[_missedFixingsIndices.length - 1];
        _missedFixingsIndices.pop();

        emit MissedFixingUpdated(block.timestamp, missedFixingIndex);
    }

    /*******************
     * Virtual Methods *
     *******************/
    function computeFactors(uint64 spotAtPeriodStart, uint64 spotAtPeriodEnd, uint64 premiumAtPeriodEnd) internal view virtual
     returns(int64[] memory longRateFactors, int64[] memory shortRateFactors);
    function executeMarginCall(uint64 prevSpot, Fixing memory lastFixing) internal virtual;
    function transfer(int64[] memory longRateFactors, int64[] memory shortRateFactors) internal virtual;

    /*******************
     * Private Methods *
     *******************/
     function addTemporaryMissingFixings(uint64 lastSpot, uint lastFixingTimestamp, uint nextFixingTimestamp) private {
        uint lastFixingIndex = _fixings.length - 1;
        uint numberOfMissedFixings = uint((nextFixingTimestamp - lastFixingTimestamp) / _currentFixingUpdateInterval) - 1;

        // No margin call will be executed since spot perf is 0
        for (uint i = 0; i < numberOfMissedFixings; i++) {
            lastFixingTimestamp += _currentFixingUpdateInterval;

            Fixing memory fixing = Fixing(lastFixingTimestamp, lastSpot, 0, 0, 0);

            for (uint8 l = 0; l < 6; ++l) {
                _longRateIndices[l].push(_longRateIndices[l][_longRateIndices[l].length - 1]);
                _shortRateIndices[l].push(_shortRateIndices[l][_shortRateIndices[l].length - 1]);
            }

            _fixings.push(fixing);

            lastFixingIndex++;
            _missedFixingsIndices.push(lastFixingIndex);

            emit FixingMissed(lastFixingTimestamp, lastFixingIndex);
        }
    }

    function init(Terms term) private {
        (_currentFixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);

        _currentMidFixingInterval = _currentFixingUpdateInterval >> 1;
        _currentAccrualYF = Utils.getAccrualYF(_currentFixingUpdateInterval, _expiryInterval);

        for (uint8 i = 0; i < 6; i++) {
            _longRateIndices[i].push(0);
            _shortRateIndices[i].push(0);

            _longRatios[i] = 0;
            _shortRatios[i] = 0;
        }
    }
}