// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../interfaces/ierc20.sol";
import "../interfaces/ixmmpool.sol";
import "../libraries/math.sol";
import "../libraries/safemath.sol";
import "../libraries/utils.sol";
import "../structures/fixing.sol";
import "../structures/position.sol";
import "../enums.sol";

abstract contract XMMPool is IXMMPool {
    /**********
     * Events *
     **********/
     event OwnerChanged(uint indexed timestamp, address prevOwner, address newOwner);
     event Deposit(address indexed from, uint indexed timestamp, Position position);
     event PositionReduced(address indexed from, uint indexed timestamp, uint128 amount);
     event FixingMissed(uint indexed fixingTimestamp, uint fixingIndex);
     event MissedFixingUpdated(uint indexed timestamp, uint fixingIndex);
     event UpdateFrequencyChanged(uint indexed timestamp, uint fixingIndex, uint newFrequency);

     event FeeChanged(uint indexed timestamp, uint8 oldFee, uint8 newFee);
     event PenaltyChanged(uint indexed timestamp, uint8 oldPenalty, uint8 newPenalty);

    /*****************
     * The modifiers *
     *****************/
    modifier onlyOwner {
        require(msg.sender == Owner, "Only owner");
        _;
    }

    modifier hasMinDeposit(uint128 amount) {
        require(amount >= MinDeposit, "Min deposit");
        _;
    }

    modifier hasMinWithdrawal(uint128 amount) {
        require(amount >= MinWithdrawal, "Min amt");
        _;
    }

    modifier isActive {
        require(IsActivated, "Not activated");
        _;
    }

    modifier isLeveragePossible(Leverage leverage) {
        require(leverage == Leverage.One || LeverageIsActive, "No Leverage");
        _;
    }

    address public Owner;
    bool public IsActivated;

    /***********************
     * Contract Properties *
     ***********************/
    // ----------------------
    // - Private properties -
    // ----------------------
    uint8 private _decimals;

    uint internal _currentFixingUpdateInterval;
    uint internal _currentMidFixingInterval;
    uint64 private _currentAccrualYF;

    uint internal _expiryInterval;
    uint64 private _expiryYearFraction;
    
    uint[] private _missedFixingsIndices;

    // The positions by depositors
    mapping(address => Position[]) internal _positions;

    // The list of fixings
    Fixing[] internal _fixings;

    // Fixing Frequency Changes
    uint[] internal _fixingIndexOfFreqUpdate;
    uint[] internal _fixingUpdateIntervals;
    uint[] internal _midFixingUpdateIntervals;
    uint64[] private _accrualYFs;

    // Private fields to manage long positions
    mapping(uint8 => uint64) private _longRatios;
    mapping(uint8 => int64[]) private _longRateIndices;

    // Private fields to manage short positions
    mapping(uint8 => uint64) private _shortRatios;
    mapping(uint8 => int64[]) private _shortRateIndices;

    // ---------------------
    // - Public properties -
    // ---------------------
    /// @notice The start date of the XMM
    uint public StartDate;

    /// @notice The Term of the XMM
    Terms public Term;

    /// @notice The penalty if position is not held for min accrual period
    uint8 public Penalty;

    /// @notice The minimum deposit size
    uint128 public MinDeposit;

    /// @notice The minimum withdrawal size
    uint128 public MinWithdrawal;

    /// @notice Gets the leverage status
    bool public LeverageIsActive;

    /// @notice The daily fee charged on the position
    // The fee is expressed in percent of a basis point
    uint8 public Fee;

    /// @notice The total amount of long positions, by leverage index
    mapping(uint8 => uint128) internal TotalLongPositions;

    /// @notice The total amount of short positions, by leverage index
    mapping(uint8 => uint128) internal  TotalShortPositions;
    

    /*************
     * Functions *
     *************/
    constructor(address owner, uint8 decimals, Terms term, uint8 fee, uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio) {
        Owner = owner;
        IsActivated = false;
        Term = term;
        MinDeposit = uint128(minDeposit) * uint128(10 ** decimals);
        MinWithdrawal = (MinDeposit * minWithdrawalRatio) / 100;
        Penalty = penalty;
        Fee = fee;

        _decimals = decimals;
        init(term);
    }

    /// @notice Changes the leverage status
    function changeLeverageStatus(bool status) external onlyOwner {
        LeverageIsActive = status;
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
    function getPoolPositions(Leverage leverage) external view returns(uint128 long, uint128 short) {
        return (TotalLongPositions[uint8(leverage)], TotalShortPositions[uint8(leverage)]);
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

    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner) external onlyOwner {
        Owner = newOwner;
        emit OwnerChanged(block.timestamp, msg.sender, newOwner);
    }

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
        
        _fixingIndexOfFreqUpdate.push(_fixings.length);
        _currentMidFixingInterval = _currentFixingUpdateInterval >> 1;
        _currentAccrualYF = Utils.getAccrualYF(_currentFixingUpdateInterval, _expiryInterval);

        _fixingUpdateIntervals.push(_currentFixingUpdateInterval);
        _midFixingUpdateIntervals.push(_currentMidFixingInterval);
        _accrualYFs.push(_currentAccrualYF);

        emit UpdateFrequencyChanged(block.timestamp, _fixings.length, _currentFixingUpdateInterval);
    }

    /// @notice Closes all the positions held by a user.
    function closeAllPositions() external {
        if (_positions[msg.sender].length > 0) {
            for (uint32 i = 0; i < _positions[msg.sender].length; i++) closePosition(i);
        }
    }

    /// @notice Closes a position
    function closePosition(uint32 positionIndex) public {
        if (_positions[msg.sender].length > positionIndex) {
            reducePosition(positionIndex, _positions[msg.sender][positionIndex].amount);
        }
    }

    /// @notice Returns user's position at given index
    /// @param positionIndex The index of the position
    function getPosition(uint32 positionIndex) external view returns(Position memory) {
        require(_positions[msg.sender].length > positionIndex, "Bad position index");
        return _positions[msg.sender][positionIndex];
    }

    /// @notice Returns the positions held by a user
    function getPositions() external view returns(Position[] memory) {
        return _positions[msg.sender];
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public virtual;

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

    /// @notice Sets the new Fee for the pool
    function setNewFee(uint8 newFee) external onlyOwner {
        emit FeeChanged(block.timestamp, Fee, newFee);
        Fee = newFee;
    }

    /// @notice Sets the new Penalty for the pool
    function setNewPenalty(uint8 newPenalty) external onlyOwner {
        emit PenaltyChanged(block.timestamp, Penalty, newPenalty);
        Penalty = newPenalty;
    }
    
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

    function getExistingPosition(address user, uint fixingIndex, Leverage leverage) internal view returns(bool, uint32) {
        Position[] storage positions = _positions[user];

        for (uint32 i = 0; i < positions.length; i++) {
            Position storage position = positions[i];
            if (position.leverage == leverage && position.fixingIndex0 == fixingIndex) return (true, i);
        }

        return (false, uint32(positions.length));
    }

    function writeDeposit(address user, uint lastFixingIndex, LongShort longShort, uint128 amount, Leverage leverage) internal {
        uint timestamp = Utils.getTimeStamp(block.timestamp, _fixings[lastFixingIndex].timestamp, _currentFixingUpdateInterval);

        // If position is opened after mid update interval, the next fixing is used
        if (block.timestamp > timestamp + _currentMidFixingInterval) {
            timestamp += _currentFixingUpdateInterval;
            lastFixingIndex++;
        }

        (bool hasPosition, uint32 positionIndex) = getExistingPosition(user, lastFixingIndex, leverage);
        Position memory position;

        if (hasPosition) {
            position = _positions[user][positionIndex];
        } else {
            position = Position(positionIndex, longShort, leverage, lastFixingIndex, timestamp, timestamp + _expiryInterval, amount);
        }

        _positions[user].push(position);
                
        if (longShort == LongShort.Long) {
            TotalLongPositions[uint8(leverage)] = SafeMath.add128(TotalLongPositions[uint8(leverage)], amount);
        } else {
            TotalShortPositions[uint8(leverage)] = SafeMath.add128(TotalShortPositions[uint8(leverage)], amount);
        }

        setRatios();

        emit Deposit(msg.sender, block.timestamp, position);
    }

    /// @notice Returns the penalty amount
    function applyPenalty(uint128 amount) internal view returns(uint128) {
        return uint128((uint136(amount) * Penalty) / 1_000_000);
    }

    function computeFactors(uint64 spotAtPeriodStart, uint64 spotAtPeriodEnd, uint64 premiumAtPeriodEnd) private view
    returns(int64[] memory longRateFactors, int64[] memory shortRateFactors) {
        uint64 premiumPerf = Math.mult(premiumAtPeriodEnd, _currentAccrualYF);
        int64 spotPerf = Math.subToSigned(spotAtPeriodEnd, spotAtPeriodStart);

        longRateFactors = new int64[](6);
        shortRateFactors = new int64[](6);

        if (spotPerf == 0) return (longRateFactors, shortRateFactors);

        // If spot went up, the Short positions pay the Long positions
        if (spotPerf > 0) {
            for (uint8 i = 0; i < 6; i++) {
                longRateFactors[i] = Math.multSigned(Utils.getLeverageFactor(i), int64(Math.mult(_longRatios[i], premiumPerf)));
                shortRateFactors[i] = Math.multSigned(Utils.getLeverageFactor(i), -int64(premiumPerf));
            }
            
        // Else, Long positions pay Short positions
        } else {
            for (uint8 i = 0; i < 6; i++) {
                longRateFactors[i] = Math.multSigned(Utils.getLeverageFactor(i), -int64(premiumPerf));
                shortRateFactors[i] = Math.multSigned(Utils.getLeverageFactor(i), int64(Math.mult(_shortRatios[i], premiumPerf)));
            }
        }

        return (longRateFactors, shortRateFactors);
    }

    function executeMarginCall(uint64 prevSpot, Fixing memory lastFixing) private {
        (int64[] memory longRateFactors, int64[] memory shortRateFactors) = computeFactors(prevSpot, lastFixing.spot, lastFixing.premium);

        transfer(longRateFactors, shortRateFactors);

        for (uint8 k = 0; k < 6; k++) {
            _longRateIndices[k].push(Math.addSigned(_longRateIndices[k][_longRateIndices[k].length - 1], longRateFactors[k]));
            _shortRateIndices[k].push(Math.addSigned(_shortRateIndices[k][_shortRateIndices[k].length - 1], shortRateFactors[k]));
        }
    }

    function transfer(int64[] memory longRateFactors, int64[] memory shortRateFactors) private {
        for (uint8 i = 0; i < 6; i++) {
            // If longRateFactor is negative, long pays short
            // longRateFactor is equal to the premium accrual
            if (longRateFactors[i] < 0)  { transferLongToShort(i, uint64(-longRateFactors[i])); }
            // else, shortRateFactor is negative and equal to the accrued premium
            else { transferShortToLong(i, uint64(-shortRateFactors[i])); }
        }
    }

    function transferShortToLong(uint8 index, uint64 netPerf) private {
        if (netPerf == 0) return;

        uint256 totalShort = uint256(TotalShortPositions[index]);
        if (totalShort == 0 || TotalLongPositions[index] == 0) return;

        uint128 transferAmt = uint128((totalShort * netPerf) >> 32);
        TotalShortPositions[index] = SafeMath.sub128(TotalShortPositions[index], transferAmt);
        TotalLongPositions[index] = SafeMath.add128(TotalLongPositions[index], transferAmt);

        setRatios();
    }

    function transferLongToShort(uint8 index, uint64 netPerf) private {
        if (netPerf == 0) return;

        uint256 totalLong = uint256(TotalLongPositions[index]);
        if (totalLong == 0 || TotalShortPositions[index] == 0) return;

        uint128 transferAmt = uint128((totalLong * netPerf) >> 32);
        TotalLongPositions[index] = SafeMath.sub128(TotalLongPositions[index], transferAmt);
        TotalShortPositions[index] = SafeMath.add128(TotalShortPositions[index], transferAmt);

        setRatios();
    }

    function getRate(LongShort longShort, Leverage leverage, uint fixingIndex0) internal view returns(int64) {
        uint8 index = uint8(leverage);
        int64 currentIndexValue = longShort == LongShort.Long ? _longRateIndices[index][_fixings.length - 1] : _shortRateIndices[index][_fixings.length - 1];
        int64 initialIndexValue = longShort == LongShort.Long ? _longRateIndices[index][fixingIndex0] : _shortRateIndices[index][fixingIndex0];
        return Math.subSigned(currentIndexValue, initialIndexValue);
    }

    function setRatios() internal {
        setLongRatios();
        setShortRatios();
    }

    function setLongRatios() private {
        for (uint8 i = 0; i < 6; i++) {
            uint128 totalLong = TotalLongPositions[i];

            if (totalLong == 0) {
                _longRatios[i] = 0;
            } else {
                uint160 short = uint160(TotalShortPositions[i]) << 32;
                _longRatios[i] = uint64(short / totalLong);
            }
        }
    }

    function setShortRatios() private {
        for (uint8 i = 0; i < 6; i++) {
            uint128 totalShort = TotalShortPositions[i];

            if (totalShort == 0) {
                _shortRatios[i] = 0;
            } else {
                uint160 long = uint160(TotalLongPositions[i]) << 32;
                _shortRatios[i] = uint64(long / totalShort);
            }
        }
    }

    function init(Terms term) private {
        (_currentFixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);

        _fixingIndexOfFreqUpdate.push(0);
        _fixingUpdateIntervals.push(_currentFixingUpdateInterval);

        _currentMidFixingInterval = _currentFixingUpdateInterval >> 1;
        _midFixingUpdateIntervals.push(_currentMidFixingInterval);

        _currentAccrualYF = Utils.getAccrualYF(_currentFixingUpdateInterval, _expiryInterval);
        _accrualYFs.push(_currentAccrualYF);

        for (uint8 i = 0; i < 6; i++) {
            _longRateIndices[i].push(0);
            _shortRateIndices[i].push(0);

            _longRatios[i] = 0;
            _shortRatios[i] = 0;
        }
    }
}