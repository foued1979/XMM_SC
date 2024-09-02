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

    modifier isActive {
        require(IsActivated, "Not activated");
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

    uint private _fixingUpdateInterval;
    uint private _midFixingInterval;
    uint private _expiryInterval;
    uint64 private _expiryYearFraction;
    uint64 private _acrualYF;

    uint[] private _missedFixingsIndices;

    // The positions by depositors
    mapping(address => Position[]) internal _positions;

    // The list of fixings
    Fixing[] internal _fixings;

    // Private fields to manage long positions
    uint128 private _marginCallLong;
    uint64 private _longRatio;
    int64[] private _longRateIndex;

    // Private fields to manage short positions
    uint128 private _marginCallShort;
    int64 private _shortRatio;
    uint64[] private _shortRateIndex;

    // ---------------------
    // - Public properties -
    // ---------------------
    /// @notice The start date of the XMM
    uint public StartDate;

    /// @notice The Term of the XMM
    Terms public Term;

    /// @notice The minimum deposit size
    uint128 public MinDeposit;

    /// @notice The daily fee charged on the position
    // The fee is expressed in percent of a basis point
    uint16 public Fee;

    /// @notice The total amount of long positions
    uint128 public TotalLongPositions;

    /// @notice The total amount of short positions
    uint128 public TotalShortPositions;
    

    /*************
     * Functions *
     *************/
    constructor(address owner, uint8 decimals, Terms term, uint16 fee, uint64 minDeposit) {
        Owner = owner;
        IsActivated = false;
        Term = term;
        MinDeposit = uint128(minDeposit) * uint128(10 ** decimals);
        Fee = fee;

        _decimals = decimals;
        (_fixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);
        _midFixingInterval = _fixingUpdateInterval / 2;

        _acrualYF = Math.div(uint64(_fixingUpdateInterval) << 32, uint64(_expiryInterval) << 32);

        _longRateIndex.push(Math.One_32);
        _shortRateIndex.push(Math.One_32);

        getRatios();
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
    function setFirstFixing(uint64 spot, uint64 strike, uint64 volatility, uint64 optionPremium) external onlyOwner {
        if (_fixings.length > 0) return;

        // The start date is the 1st timestamp
        StartDate = Utils.getTimeStamp(block.timestamp, 0, Utils._fixingUpdateInterval);
        
        // We can update only from 5 minutes before the first fixing time
        require(block.timestamp - StartDate <= 300, "Not sync");
        
        Fixing memory fixing = Fixing(StartDate, spot, strike, volatility, optionPremium);
        _fixings.push(fixing);

        IsActivated = true;
    }

    /// @notice Sets the latest fixing for the XMM
    function setFixing(uint64 spot, uint64 strike, uint64 volatility, uint64 optionPremium) external onlyOwner returns(bool) {
        Fixing storage lastFixing = _fixings[_fixings.length - 1];
        uint nextFixingTimestamp = Utils.getTimeStamp(block.timestamp, lastFixing.timestamp, _fixingUpdateInterval);

        uint threshold = 0;
            // If the update interval is less than or equal to 5 min, the threshold is 1 min
            if (_fixingUpdateInterval <= Utils.FIVE_MINUTES_UPDATE_INTERVAL) threshold = 60;
            // Else if update interval is less than or equal to 15 min, the threshold is 2 min
            else if (_fixingUpdateInterval <= Utils.FIFTEEN_MINUTES_UPDATE_INTERVAL) threshold = 120;
            // Otherwise the threshold is 3 min
            else threshold = 180;
        
        if (nextFixingTimestamp == lastFixing.timestamp) {
            // If the update is done within the threshold, we update the fixing
            if (Math.sub(nextFixingTimestamp + _fixingUpdateInterval, block.timestamp) <= threshold) {
                nextFixingTimestamp += _fixingUpdateInterval;
            // Otherwise, we are too early to update the fixing
            } else return false;
        }
        else if (nextFixingTimestamp == lastFixing.timestamp + _fixingUpdateInterval) {
            // If the update is done after the threshold, the fixing is missed
            if (Math.sub(block.timestamp, nextFixingTimestamp) > threshold) return false;
        }
        // However, if at least one fixings has been missed (e.g. due to a technical error), we fill in missing fixings
        // with last know spot value, and we will update the missing fixings later.
        else {
            // If we are threshold minutes before the next update, we adjust the next fixing timestamp
            if (Math.absSub(nextFixingTimestamp + _fixingUpdateInterval, block.timestamp) <= threshold) nextFixingTimestamp += _fixingUpdateInterval;
            // However if we are outside the threshold, above or below the next fixing timestamp, then the fixing is missed
            else if (Math.absSub(block.timestamp, nextFixingTimestamp) > threshold) return false;

            // We add temporary fixings for the missed fixings
            // The missed fixings can be manually updated later
            addTemporaryMissingFixings(lastFixing.spot, lastFixing.timestamp, nextFixingTimestamp);
        }

        Fixing memory fixing = Fixing(nextFixingTimestamp, spot, strike, volatility, optionPremium);
        executeMarginCalls(lastFixing.spot, lastFixing.timestamp, fixing);
        
        _fixings.push(fixing);
        return true;
    }

    /// @notice In case a fixing update has been missed, owner can update the missed past fixings
    ///         To avoid multiple updates or wrong fixing updates, only the missed fixing index can be updated 1 time
    function updateMissedFixing(uint missedFixingIndex, uint64 spot, uint64 strike, uint64 volatility, uint64 optionPremium) external onlyOwner {
        for (uint i = 0; i < _missedFixingsIndices.length; i++) {
            if (_missedFixingsIndices[i] == missedFixingIndex) {
                Fixing storage prevFixing = _fixings[missedFixingIndex - 1];
                Fixing storage fixing = _fixings[missedFixingIndex];

                // We update the fixing ith the proper market data
                fixing.spot = spot;
                fixing.strike = strike;
                fixing.volatility = volatility;
                fixing.premium = optionPremium;

                // We compute the new interest factor for both long and short side
                // The updateIndex method also proceeds to margin call
                (int64 longRateFactor, int64 shortRateFactor) = computeMissedFactors(prevFixing.timestamp, fixing.timestamp, prevFixing.spot, fixing.spot, optionPremium);

                // We update all the indices from missedFixingIndex to the last fixing index
                // The update factors are longRateFactor for the long side and shortRateFactor for the short side
                for (uint j = missedFixingIndex; j < _fixings.length; j++)
                {
                    _longRateIndex[j] = Math.addSigned(_longRateIndex[j - 1], longRateFactor);
                    _shortRateIndex[j] = Math.addSigned(_shortRateIndex[j - 1], shortRateFactor);
                }

                _missedFixingsIndices[i] = _missedFixingsIndices[_missedFixingsIndices.length - 1];
                _missedFixingsIndices.pop();

                emit MissedFixingUpdated(block.timestamp, missedFixingIndex);
                return;
            }
        }
    }

    function addTemporaryMissingFixings(int64 lastSpot, uint lastFixingTimestamp,  uint nextFixingTimestamp) private {
        uint lastFixingIndex = _fixings.length - 1;
        uint numberOfMissedFixings = uint((nextFixingTimestamp - lastFixingTimestamp) / _fixingUpdateInterval) - 1;

        // No margin call will be executed since spot perf is 0
            int64 longRateFactor = _longRateIndex[_longRateIndex.length - 1];
            int64 shortRateFactor = _shortRateIndex[_shortRateIndex.length - 1];

        for (uint i = 0; i < numberOfMissedFixings; i++) {
            lastFixingTimestamp += _fixingUpdateInterval;

            Fixing memory fixing = Fixing(lastFixingTimestamp, lastSpot, 0, 0, 0);

            _longRateIndex.push(longRateFactor);
            _shortRateIndex.push(shortRateFactor);

            _fixings.push(fixing);

            lastFixingIndex++;
            _missedFixingsIndices.push(lastFixingIndex);

            emit FixingMissed(lastFixingTimestamp, lastFixingIndex);
        }
    }

    function executeMarginCalls(uint64 prevSpot, uint prevFixingTimestamp, Fixing memory lastFixing) private {
        uint64 d = uint64((lastFixing.timestamp - prevFixingTimestamp) / _fixingUpdateInterval) << 32;
        uint64 premiumPerf = Math.mult(lastFixing.premium, Math.mult(d, _acrualYF));

        int64 longRateFactor = 0;
        int64 shortRateFactor = 0;
        int64 adjustedRate = 0;

        int64 spotPerf = Math.subSigned(lastFixing.spot, prevSpot);

        // If the spot has not moved, there is no margin call
        // Index is constant for the period
        if (spotPerf == 0) {
            longRateFactor = _longRateIndex[_longRateIndex.length - 1];
            shortRateFactor = _shortRateIndex[_shortRateIndex.length - 1];

            _longRateIndex.push(longRateFactor);
            _shortRateIndex.push(shortRateFactor);

            return;
        }

        // If spot went up, the Short positions pay the Long positions
        if (spotPerf > 0) {
            longRateFactor = Math.addSigned(_longRateIndex[_longRateIndex.length - 1], Math.mult(_longRatio, premiumPerf));
            shortRateFactor = Math.addSigned(_shortRateIndex[_shortRateIndex.length - 1], -premiumPerf);
            transferShortToLong(premiumPerf);
        // Else, Long positions pay Short positions
        } else {
            longRateFactor = Math.addSigned(_longRateIndex[_longRateIndex.length - 1], -premiumPerf);
            shortRateFactor = Math.addSigned(_shortRateIndex[_shortRateIndex.length - 1], Math.mult(_shortRatio, premiumPerf));
            transferLongToShort(premiumPerf);
        }

        _longRateIndex.push(longRateFactor);
        _shortRateIndex.push(shortRateFactor);
    }

    function computeMissedFactors(uint periodStart, uint periodEnd, uint64 spotAtPeriodStart, uint64 spotAtPeriodEnd, uint64 premiumAtPeriodEnd) private 
    returns(int64 longRateFactor, int64 shortRateFactor) {
        uint64 d = uint64((periodEnd - periodStart) / _fixingUpdateInterval) << 32;
        uint64 premiumPerf = Math.mult(premiumAtPeriodEnd, Math.mult(d, _acrualYF));

        int64 spotPerf = Math.subSigned(spotAtPeriodEnd, spotAtPeriodStart);

        if (spotPerf == 0) return (Math.One_32, Math.One_32);

        // If spot went up, the Short positions pay the Long positions
        if (spotPerf > 0) {
            longRateFactor = Math.mult(_longRatio, premiumPerf);
            shortRateFactor = -premiumPerf;
            transferShortToLong(premiumPerf);
        // Else, Long positions pay Short positions
        } else {
            longRateFactor = -premiumPerf;
            shortRateFactor = Math.mult(_shortRatio, premiumPerf);
            transferLongToShort(premiumPerf);
        }

        return (longRateFactor, shortRateFactor);
    }

    function transferShortToLong(uint64 netPerf) private {
        if (netPerf == 0 || TotalShortPositions == 0) return;

        uint128 transfer = uint128(TotalShortPositions >> Math.max(int8(_decimals - 2), 0));
        transfer = uint128((uint256(transfer) * netPerf) >> 32);

        if (_marginCallLong >= transfer) {
            _marginCallLong = SafeMath.SafeSub128(_marginCallLong, transfer);
        } else {
            transfer = SafeMath.SafeSub128(transfer, _marginCallLong);
            _marginCallShort = SafeMath.SafeAdd128(_marginCallShort, transfer);
        }
    }

    function transferLongToShort(uint64 netPerf) private {
        if (netPerf == 0 || TotalLongPositions == 0) return;

        uint128 transfer = uint128(TotalLongPositions >> Math.max(int8(_decimals - 2), 0));
        transfer = uint128((transfer * netPerf) >> 32);

        if (_marginCallShort >= transfer) {
            _marginCallShort = SafeMath.SafeSub128(_marginCallShort, transfer);
        } else {
            transfer = SafeMath.SafeSub128(transfer, _marginCallShort);
            _marginCallLong = SafeMath.SafeAdd128(_marginCallLong, transfer);
        }
    }

    function getRate(LongShort longShort, int64 proRata, int64 index0) private view returns(int64) {
        must be reviewed since index is a sum
        int64 currentIndex = longShort == LongShort.Long ? _longRateIndex[_fixings.length - 1] : _shortRateIndex[_fixings.length - 1];
        return Math.mult(proRata, Math.div(currentIndex, index0));
    }

    function getRatios() private {
        _longRatio = getLongRatio();
        _shortRatio = getShortRatio();
    }

    function getLongRatio() private view returns(int64) {
        if (TotalLongPositions == 0) return 0;
        uint256 short = uint256(TotalShortPositions) << 32;
        return int64(uint64(short / TotalLongPositions));
    }

    function getShortRatio() private view returns(int64) {
        if (TotalShortPositions == 0) return 0;
        uint256 long = uint256(TotalLongPositions) << 32;
        return int64(uint64(long / TotalShortPositions));
    }
}