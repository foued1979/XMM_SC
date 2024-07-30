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
    // Private properties
    uint8 private _decimals;

    uint private _fixingUpdateInterval;
    uint private _midFixingInterval;
    uint private _expiryInterval;
    int64 private _expiryYearFraction;
    int64 private _acrualYF;

    uint[] private _missedFixingsIndices;

    // The positions by depositors
    mapping(address => Position[]) internal _positions;

    // Public properties
    /// @notice The start date of the XMM
    uint public StartDate;

    /// @notice The Term of the XMM
    Terms public Term;

    /// @notice The minimum deposit size
    uint128 public MinDeposit;

    /// @notice The list of fixings
    Fixing[] public Fixings;

    /// @notice The total amount of long positions
    uint128 public TotalLongPositions;
    uint128 private _marginCallLong;
    int64 private _longRatio;
    int64[] private _longRateIndex;

    /// @notice The total amount of short positions
    uint128 public TotalShortPositions;
    uint128 private _marginCallShort;
    int64 private _shortRatio;
    int64[] private _shortRateIndex;

    /*************
     * Functions *
     *************/
    constructor(address owner, uint8 decimals, Terms term, uint64 minDeposit) {
        Owner = owner;
        _decimals = decimals;
        Term = term;
        MinDeposit = (uint128(minDeposit) * uint128(10 ** decimals)) / uint128(2 ** 32);

        (_fixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);
        _midFixingInterval = _fixingUpdateInterval / 2;

        StartDate = Utils.getTimeStamp(block.timestamp, 0, _fixingUpdateInterval);

        _acrualYF = Math.div(int64(uint64(_fixingUpdateInterval) << 32), int64(uint64(_expiryInterval) << 32));

        _longRateIndex.push(Math.One_32);
        _shortRateIndex.push(Math.One_32);

        getRatios();
    }

    /// @notice Gets the term of the XMM
    function getTerm() external view returns(Terms) {
        return Term;
    }

    /// @notice Gets the fixings
    function getFixings() external view onlyOwner returns(Fixing[] memory) {
        return Fixings;
    }

    /// @notice Gets the fixings `from` index `to` index
    function getFixingsFromTo(uint from, uint to) external view onlyOwner returns(Fixing[] memory) {
        if (to + 1 > Fixings.length) to = Fixings.length - 1;

        Fixing[] memory res = new Fixing[](to - from + 1);
        for (uint i = from; i <= to; i++) res[i - from] = Fixings[i];
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

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public virtual;

    /// @notice Returns the positions held by a user
    function getPositions() external view returns(Position[] memory) {
        return _positions[msg.sender];
    }

    /// @notice Returns user's position at given index
    /// @param positionIndex The index of the position
    function getPosition(uint32 positionIndex) external view returns(Position memory) {
        require(_positions[msg.sender].length > positionIndex, "Bad position index");
        return _positions[msg.sender][positionIndex];
    }

    /// @notice Sets the first fixing and activates the pool
    function setFirstFixing(uint64 spot, uint64 strike, uint64 volatility, int64 optionPremium) external onlyOwner {
        if (Fixings.length > 0) return;

        uint firstTimestamp = Utils.getTimeStamp(block.timestamp, StartDate, Utils.ONE_HOUR_UPDATE_INTERVAL);
        
        // We can update only from 5 minutes before the first fixing time
        require(block.timestamp > firstTimestamp || firstTimestamp - block.timestamp <= 300, "Not sync");
        
        Fixing memory fixing = Fixing(firstTimestamp, spot, strike, volatility, optionPremium);
        Fixings.push(fixing);

        IsActivated = true;
    }

    /// @notice Sets the latest fixing for the XMM
    function setFixing(uint64 spot, uint64 strike, uint64 volatility, int64 optionPremium) external onlyOwner {
        Fixing storage lastFixing = Fixings[Fixings.length - 1];
        uint nextFixingTimestamp = Utils.getTimeStamp(block.timestamp, lastFixing.timestamp, _fixingUpdateInterval);
        
        if (block.timestamp > nextFixingTimestamp) {
            if (nextFixingTimestamp == lastFixing.timestamp ) {
                // If the update is 5 minutes (or less) before the next fixing time, we accept it as the next fixing
                // This functionality is implemented to enable cases where significant number of fixings have to be pushed:
                // -> in such a case, we may start to compute fixings slightly before exact update interval timestamp
                if (nextFixingTimestamp + _fixingUpdateInterval - block.timestamp <= 300) {
                    nextFixingTimestamp += _fixingUpdateInterval;
                } else return;
            }
            // However, if at least one fixings has been missed (e.g. due to a technical error), we fill in missing fixings
            // with last know spot value, and we will update the missing fixings later.
            else if (nextFixingTimestamp > lastFixing.timestamp + 2 * _fixingUpdateInterval - 300) {
                nextFixingTimestamp = addTemporaryMissingFixings(Fixings.length - 1, lastFixing.spot, lastFixing.timestamp, nextFixingTimestamp);
            }
        }

        Fixing memory fixing = Fixing(nextFixingTimestamp, spot, strike, volatility, optionPremium);
        executeMarginCalls(lastFixing.spot, lastFixing.timestamp, fixing);
        
        Fixings.push(fixing);
    }

    /// @notice In case a fixing update has been missed, owner can update the missed past fixings
    ///         To avoid multiple updates or wrong fixing updates, only the missed fixing index can be updated 1 time
    function updateMissedFixing(uint missedFixingIndex, uint64 spot, uint64 strike, uint64 volatility, int64 optionPremium) external onlyOwner {
        for (uint i = 0; i < _missedFixingsIndices.length; i++) {
            if (_missedFixingsIndices[i] == missedFixingIndex) {
                Fixing storage prevFixing = Fixings[missedFixingIndex - 1];
                Fixing storage fixing = Fixings[missedFixingIndex];

                fixing.spot = spot;
                fixing.strike = strike;
                fixing.volatility = volatility;
                fixing.premium = optionPremium;

                // We compute the new interest factor for both long and short side
                // The updateIndex method also proceeds to margin call
                (int64 longRateFactor, int64 shortRateFactor) = updateIndex(prevFixing.timestamp, fixing.timestamp, prevFixing.spot, fixing.spot, optionPremium);

                // We update all the indices from missedFixingIndex to the last fixing index
                // The update factors are longRateFactor for the long side and shortRateFactor for the short side
                for (uint j = missedFixingIndex; j < Fixings.length; j++)
                {
                    _longRateIndex[j] = Math.mult(_longRateIndex[j - 1], longRateFactor);
                    _shortRateIndex[j] = Math.mult(_shortRateIndex[j - 1], shortRateFactor);
                }

                _missedFixingsIndices[i] = _missedFixingsIndices[_missedFixingsIndices.length - 1];
                _missedFixingsIndices.pop();
                return;
            }
        }
    }

    function addTemporaryMissingFixings(uint lastFixingIndex, uint64 lastSpot, uint lastFixingTimestamp,  uint nextFixingTimestamp) private returns(uint256) {
        uint numberOfMissedFixings = uint((nextFixingTimestamp - lastFixingTimestamp) / _fixingUpdateInterval) - 1;

        // If update time is less than 5 minutes from next fixing time, we add 1 more missing fixing
        // Latest premium will be updated for the next fixing 
        if (nextFixingTimestamp + _fixingUpdateInterval - block.timestamp <= 300) numberOfMissedFixings++;

        for (uint i = 0; i < numberOfMissedFixings; i++) {
            lastFixingTimestamp += _fixingUpdateInterval;

            Fixing memory fixing = Fixing(lastFixingTimestamp, lastSpot, 0, 0, 0);

            // No margin call will be executed since spot perf is 0
            int64 longRateFactor = _longRateIndex[_longRateIndex.length - 1];
            int64 shortRateFactor = _shortRateIndex[_shortRateIndex.length - 1];

            _longRateIndex.push(longRateFactor);
            _shortRateIndex.push(shortRateFactor);

            Fixings.push(fixing);
            lastFixingIndex++;
            _missedFixingsIndices.push(lastFixingIndex);
        }

        lastFixingTimestamp += _fixingUpdateInterval;

        return lastFixingTimestamp;
    }

    function executeMarginCalls(uint64 prevSpot, uint prevFixingTimestamp, Fixing memory lastFixing) private {
        int64 d = int64(uint64((lastFixing.timestamp - prevFixingTimestamp) / _fixingUpdateInterval)) << 32;
        int64 premiumPerf = Math.mult(lastFixing.premium, Math.mult(d, _acrualYF));

        int64 longRateFactor = 0;
        int64 shortRateFactor = 0;
        int64 adjustedRate = 0;

        int64 spotPerf = Math.subu(lastFixing.spot, prevSpot);

        if (spotPerf == 0 || premiumPerf <= 0) {
            longRateFactor = _longRateIndex[_longRateIndex.length - 1];
            shortRateFactor = _shortRateIndex[_shortRateIndex.length - 1];

            _longRateIndex.push(longRateFactor);
            _shortRateIndex.push(shortRateFactor);

            return;
        }

        // If spot went up, the Short positions pay the Long positions
        if (spotPerf > 0) {
            adjustedRate = Math.mult(_longRatio, premiumPerf);
            longRateFactor = Math.mult(_longRateIndex[_longRateIndex.length - 1], Math.add(Math.One_32, adjustedRate));
            shortRateFactor = Math.mult(_shortRateIndex[_shortRateIndex.length - 1], Math.sub(Math.One_32, adjustedRate));
            transferShortToLong(uint64(adjustedRate));
        // Else, Long positions pay Short positions
        } else {
            adjustedRate = Math.mult(_shortRatio, premiumPerf);
            longRateFactor = Math.mult(_longRateIndex[_longRateIndex.length - 1], Math.sub(Math.One_32, adjustedRate));
            shortRateFactor = Math.mult(_shortRateIndex[_shortRateIndex.length - 1], Math.add(Math.One_32, adjustedRate));
            transferLongToShort(uint64(adjustedRate));
        }

        _longRateIndex.push(longRateFactor);
        _shortRateIndex.push(shortRateFactor);
    }

    function updateIndex(uint periodStart, uint periodEnd, uint64 spotAtPeriodStart, uint64 spotAtPeriodEnd, int64 premiumAtPeriodEnd) private returns(int64, int64) {
        int64 d = int64(uint64((periodEnd - periodStart) / _fixingUpdateInterval)) << 32;
        int64 premiumPerf = Math.mult(premiumAtPeriodEnd, Math.mult(d, _acrualYF));

        int64 longRateFactor = 0;
        int64 shortRateFactor = 0;
        int64 adjustedRate = 0;

        int64 spotPerf = Math.subu(spotAtPeriodEnd, spotAtPeriodStart);

        if (spotPerf == 0 || premiumPerf <= 0) return (Math.One_32, Math.One_32);

        // If spot went up, the Short positions pay the Long positions
        if (spotPerf > 0) {
            adjustedRate = Math.mult(_longRatio, premiumPerf);
            longRateFactor = Math.add(Math.One_32, adjustedRate);
            shortRateFactor = Math.sub(Math.One_32, adjustedRate);
            transferShortToLong(uint64(adjustedRate));
        // Else, Long positions pay Short positions
        } else {
            adjustedRate = Math.mult(_shortRatio, premiumPerf);
            longRateFactor = Math.sub(Math.One_32, adjustedRate);
            shortRateFactor = Math.add(Math.One_32, adjustedRate);
            transferLongToShort(uint64(adjustedRate));
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
        int64 currentIndex = longShort == LongShort.Long ? _longRateIndex[Fixings.length - 1] : _shortRateIndex[Fixings.length - 1];
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