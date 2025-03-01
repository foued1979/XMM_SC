// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./fixingmanager.sol";
import "../enums.sol";
import "../interfaces/ierc20.sol";
import "../libraries/math.sol";
import "../libraries/utils.sol";
import "../structures/position.sol";

abstract contract XMMPool is FixingManager {
    /**********
     * Events *
     **********/
    event Deposit(address indexed from, uint indexed timestamp, Position position);
    event PositionReduced(address indexed from, uint indexed timestamp, uint128 amount);

    /*****************
     * The modifiers *
     *****************/
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

    modifier positionIsValid(uint32 positionIndex) {
        require(_positions[msg.sender].length > positionIndex, 'pos index err');
        _;
    }

    modifier fixingsAreUpToDate(uint32 positionIndex) {
        uint lastFixingDate = _fixingDates[_fixingDates.length - 1];
        (uint nextFixingTimestamp, ) = getPositionTimestamp();
        require(IsActivated && _positions[msg.sender][positionIndex].startDate < lastFixingDate && nextFixingTimestamp < lastFixingDate, 'no fixing');
        _;
    }

    /***********************
     * Contract Properties *
     ***********************/
    // ----------------------
    // - Private properties -
    // ----------------------
    uint8 internal _poolTokenDecimals;
    uint128 internal _accumulatedFee;

    // The positions by depositors
    mapping(address => Position[]) internal _positions;

    // ---------------------
    // - Public properties -
    // ---------------------

    /// @notice The penalty if position is not held for min accrual period
    uint8 public Penalty;

    /// @notice Indicates whether the PenaltyFee will apply if user offset position before maturity
    bool public ApplyPenaltyFee;

    /// @notice The minimum deposit size
    uint128 public MinDeposit;

    /// @notice The minimum withdrawal size
    uint128 public MinWithdrawal;

    /// @notice The daily fee charged on the position
    // The fee is expressed in percent of a basis point
    uint8 public Fee;

    /// @notice The sum of long positions by term
    uint128 public TotalLongPositions;

    /// @notice The amount of long positions, by Term
    // key => uint8(Terms)
    uint128[7] internal _longPositionsByTerm;

    // The sum of short positions by term
    uint128 public TotalShortPositions;

    /// @notice The amount of short positions, by Term
    // Key => uint8(Terms)
    uint128[7] internal _shortPositionsByTerm;
    
    /***************
     * Constructor *
     ***************/
    /// @param minDeposit The minimum deposit expressed in unit of poolToken; e.g. 10 for 10 poolToken minimum deposit
    constructor(address owner, uint8 poolTokenDecimals, address compensationToken, uint8 compensationTokenDecimals, uint currentFixingUpdateInterval, uint8 fee, uint8 penalty,
     uint64 minDeposit, uint8 minWithdrawalRatio) FixingManager(owner, compensationToken, compensationTokenDecimals, currentFixingUpdateInterval) {
        _poolTokenDecimals = poolTokenDecimals;
        MinDeposit = uint128(minDeposit) * uint128(10 ** poolTokenDecimals);
        MinWithdrawal = (MinDeposit * minWithdrawalRatio) / 100;
        Penalty = penalty;
        ApplyPenaltyFee = false;
        Fee = fee;
    }

    /*************
     * Functions *
     *************/
    function changeMinimumDeposit(uint64 minDeposit) external onlyOwner {
        MinDeposit = uint128(minDeposit) * uint128(10 ** _poolTokenDecimals);
    }

    /// @notice Gets the total accumulated fee
    function getAccumulatedFee() external view onlyOwner() returns(uint128) {
        return _accumulatedFee;
    }

    /// @notice Gets performance of mag.sender's position at the given position index 
    function getPositionPerformance(uint32 positionIndex) public view returns(int64) {
        require(positionIndex < _positions[msg.sender].length, "Index err");
        Position storage pos = _positions[msg.sender][positionIndex];

        // If position went through 0, returns 0 perf
        if (isZeroPerf(pos)) return 0;
        uint lastFixingTimestamp = _fixingDates[_fixingDates.length - 1];
        uint8 term = uint8(pos.term);

        int64 startIndex = pos.longShort == LongShort.Long ? _longRateIndices[pos.startDate][term] : _shortRateIndices[pos.startDate][term];
        int64 lastIndex = pos.longShort == LongShort.Long ? _longRateIndices[lastFixingTimestamp][term] : _shortRateIndices[lastFixingTimestamp][term];

        return Math.subSigned(lastIndex, startIndex); 
    }

    /// @notice Gets performance of all msg.sender's positions
    function getPositionPerformances() external view returns(int64[] memory perfs) {
        perfs = new int64[](_positions[msg.sender].length);

        for (uint32 i = 0; i < _positions[msg.sender].length; i++) {
            perfs[i] = getPositionPerformance(i);
        }
    }
    
    /// @notice Gets the total long and short positions for a given Term
    function getPoolPendingPositionsForTerm(Terms term) external view returns(uint128 long, uint128 short) {
        uint8 T = uint8(term);
        return (_longNotionalsForNextFixing[T], _shortNotionalsForNextFixing[T]);
    }

    /// @notice Gets the total long and short positions for a given Term
    function getPoolPositionsForTerm(Terms term) external view returns(uint128 long, uint128 short) {
        uint8 T = uint8(term);
        return (_longPositionsByTerm[T], _shortPositionsByTerm[T]);
    }
    
    /// @notice Closes all the positions held by a user.
    function closeAllPositions() external {
        for (uint32 i = 0; i < _positions[msg.sender].length; i++) closePosition(i);
    }

    /// @notice Closes a position
    function closePosition(uint32 positionIndex) public {
        if (_positions[msg.sender].length > positionIndex) {
            reducePosition(positionIndex, _positions[msg.sender][positionIndex].amount);
        }
    }

    /// @notice Creates a position on behaf of a user; e.g. if user transfers coin directly to the pool, pool owner
    //          can write the position
    /// @param amount   The amount of the position, inclusive of the fee -> if a client transfers 100 tokens, and the fee is 1 token
    //                  amount = 100 and fee = 1
    function createPositionForUser(LongShort longShort, Terms term, uint128 amount, uint128 fee, address user) external onlyOwner {
        amount -= fee;
        (uint timestamp, FixingTypes isNextFixing) = getPositionTimestamp();
        
        writeDeposit(user, timestamp, isNextFixing, longShort, term, amount, fee);
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
    function reducePosition(uint32 positionIndex, uint128 amount) public virtual returns(bool hasBeenClosed);

    /// @notice Sets the new Fee for the pool
    function setNewFee(uint8 newFee) external onlyOwner {
        Fee = newFee;
    }

    /// @notice Sets the new Penalty for the pool
    function setNewPenalty(uint8 newPenalty) external onlyOwner {
        Penalty = newPenalty;
    }

    /// @notice Sets whether the PenaltyFee will apply to users offsetting position before maturity
    function setApplyPenaltyFee(bool status) external onlyOwner {
        ApplyPenaltyFee = status;
    }

    /********************
     * Internal Methods *
     ********************/
    function getExistingPosition(address user, uint fixingDate, LongShort longShort, Terms term) internal returns(bool, Position storage) {
        Position[] storage positions = _positions[user];

        for (uint32 i = 0; i < positions.length; i++) {
            Position storage position = positions[i];
            if (position.longShort == longShort && position.term == term && position.startDate == fixingDate) return (true, position);
        }

        Position memory tmpPos = Position(uint32(_positions[user].length), longShort, term, fixingDate, fixingDate + _expiryIntervals[uint8(term)], 0, 0);
        positions.push(tmpPos);

        return (false, positions[positions.length - 1]);
    }

    function writeDeposit(address user, uint timestamp, FixingTypes isNextFixing, LongShort longShort, Terms term, uint128 amount, uint128 minFeePaid) internal {
        uint8 T = uint8(term);

        // We check if a user already has a position similar to this new order
        // Positions are equal when side, leverage and fixingIndex are the same
        (bool hasPosition, Position storage position) = getExistingPosition(user, timestamp, longShort, term);

        // If user already has a position which is equivalent to the current order
        // we just update the existing position
        if (hasPosition) {
            position.amount += amount;
            position.minFeePaid += minFeePaid;
        } else {
            position.amount = amount;
            position.minFeePaid = minFeePaid;
            
            _positions[user].push(position);
        }

        emit Deposit(user, block.timestamp, position);
           
        if (longShort == LongShort.Long) {
            // If the next fixing is used, the amount cannot be added to the current positions
            // The amount is pending to be added; when we update the fixing, we will add the pending positions
            if (isNextFixing == FixingTypes.Next) { 
                _longNotionalsForNextFixing[T] += amount; 
            } else {
                _longPositionsByTerm[T] += amount; 
                TotalLongPositions += amount; 
                }
        } else {
            // If the next fixing is used, the amount cannot be added to the current positions
            // The amount is pending to be added; when we update the fixing, we will add the pending positions
            if (isNextFixing == FixingTypes.Next) { 
                _shortNotionalsForNextFixing[T] += amount;
            } else {
                _shortPositionsByTerm[T] += amount; 
                TotalShortPositions += amount;
            }
        }
    }

    function getMinimumFee(address user, uint positionStartDate, uint positionEndDate, uint128 positionAmt) internal returns(uint128) {
        uint128 holdingPeriod = uint128(((positionEndDate - positionStartDate) / 60) >> 1);
        // 1_440 minutes within a day
        // The Fee is in %bps on a daily basis 
        uint128 minFee = uint128(uint128(Fee) * holdingPeriod * positionAmt / 1_440_000_000);
        return getRebatedMinimumFee(user, minFee);
    }

    /// @notice Gets the fee for the position
    function getPositionFee(address user, uint tradeDate, uint positionStartDate, uint positionEndDate, uint128 positionAmt, uint128 minFeePaid) internal returns(uint128) {
        // HoldingPeriod represents the number of minutes during which position is held
        uint128 holdingPeriod = uint128((tradeDate - positionStartDate) / 60);
        uint128 minHoldingPeriod = uint128(((positionEndDate - positionStartDate) / 60) >> 1);

        // If the holding period is less than the minimum holding period, Fee has already been charged
        if (holdingPeriod <= minHoldingPeriod) return 0;

        // 1_440 minutes within a day
        // The Fee is in %bps on a daily basis 
        uint128 fee = uint128(uint128(Fee) * holdingPeriod * positionAmt / 1_440_000_000) - minFeePaid;
        return getRebatedFee(user, fee);
    }

    /****************************************
     * FixingManager Methods Implementation *
     ****************************************/
    function incorporateNextNotionals() internal override {
        for (uint8 i = 0; i < _termsLength; i++) {
            TotalLongPositions += _longNotionalsForNextFixing[i];
            TotalShortPositions += _shortNotionalsForNextFixing[i];
            _longNotionalsForNextFixing[i] = 0;
            _shortNotionalsForNextFixing[i] = 0;
        }
    }

    function computeAccruals(uint64 spotAtPeriodStart, Fixing storage lastFixing) internal override
     returns(int64[] memory longRateAccruals, int64[] memory shortRateAccruals) {
        int64 spotPerf = Math.subSigned(int64(lastFixing.spot), int64(spotAtPeriodStart));

        // The factors by term
        longRateAccruals = new int64[](_termsLength);
        shortRateAccruals = new int64[](_termsLength);
        if (spotPerf == 0) return (longRateAccruals, shortRateAccruals);

        uint128[] memory amtPayerByTerm;
        uint128[] memory amtReceiverByTerm;

        // If spot went up, the Short positions pay the Long positions
        if (spotPerf > 0) {
            (amtPayerByTerm, amtReceiverByTerm) = Utils.getAccrualDetails(lastFixing.callPremia_t_1__t, _currentAccrualYFs, _shortPositionsByTerm, 
            _longPositionsByTerm, TotalShortPositions, TotalLongPositions, ShortPot);

            for (uint8 i = 0; i < _termsLength; i++) {
                // Term ratio is the ratio of perf for the given term
                longRateAccruals[i] = int64(Math.div128(amtReceiverByTerm[i], _longPositionsByTerm[i]));
                shortRateAccruals[i] = -int64(Math.div128(amtPayerByTerm[i], _shortPositionsByTerm[i]));
            }

            ShortPot = 0;
        // Else, Long positions pay Short positions
        } else {
            (amtPayerByTerm, amtReceiverByTerm) = Utils.getAccrualDetails(lastFixing.putPremia_t_1__t, _currentAccrualYFs, _longPositionsByTerm,
             _shortPositionsByTerm, TotalLongPositions, TotalShortPositions, LongPot);

            for (uint8 i = 0; i < _termsLength; i++) {
                // Term ratio is the ratio of perf for the given term
                shortRateAccruals[i] = int64(Math.div128(amtReceiverByTerm[i], _shortPositionsByTerm[i]));
                longRateAccruals[i] = -int64(Math.div128(amtPayerByTerm[i], _longPositionsByTerm[i]));
            }

            LongPot = 0;
        }

        return (longRateAccruals, shortRateAccruals);
    }

    function executeMarginCall(uint64 prevSpot) internal override {
        Fixing storage lastFixing = _fixings[_fixingDates[_fixingDates.length - 1]];
        (int64[] memory longRateFactors, int64[] memory shortRateFactors) = computeAccruals(prevSpot, lastFixing);

        transfer(longRateFactors, shortRateFactors);
        uint prevFixingTimestamp = _fixingDates[_fixingDates.length - 2];
        
        for (uint8 i = 0; i < _termsLength; i++) {
            _longRateIndices[lastFixing.timestamp].push(Math.addSigned(_longRateIndices[prevFixingTimestamp][i], longRateFactors[i]));
            _shortRateIndices[lastFixing.timestamp].push(Math.addSigned(_shortRateIndices[prevFixingTimestamp][i], shortRateFactors[i]));
        }
    }

    function transfer(int64[] memory longRateFactors, int64[] memory shortRateFactors) internal override {
        for (uint8 i = 0; i < _termsLength; i++) {
            // If longRateFactor is negative, long pays short
            // longRateFactor is equal to the premium accrual
            if (longRateFactors[i] < 0)  { transferLongToShort(i, uint64(-longRateFactors[i]), uint64(shortRateFactors[i])); }
            // else, shortRateFactor is negative and equal to the accrued premium
            else { transferShortToLong(i, uint64(-shortRateFactors[i]), uint64(longRateFactors[i])); }
        }
    }

    /********************
     * Internal Methods *
     ********************/
    function getRate(LongShort longShort, Terms term, uint positionStartDate) internal view returns(int64) {
        uint8 T = uint8(term);

        uint lastFixingDate = _fixingDates[_fixingDates.length - 1];
        int64 currentIndexValue = longShort == LongShort.Long ? _longRateIndices[lastFixingDate][T] : _shortRateIndices[lastFixingDate][T];
        int64 initialIndexValue = longShort == LongShort.Long ? _longRateIndices[positionStartDate][T] : _shortRateIndices[positionStartDate][T];

        return Math.subSigned(currentIndexValue, initialIndexValue);
    }

    /// @notice Adjusts the rate of the position, updates the amounts and returns the compensation amount, if any
    function checkPosition(Position storage position, uint128 amount, int64 rate) internal returns(int64 adjustedRate) {
        adjustedRate = rate;
        uint8 T = uint8(position.term);

        // If rate is positive, only a pro-rata interest is paid
            // If rate is negative, msg.sender shall pay the full amount due
        if (rate > 0) {
            uint64 proRata = Utils.getProRata(_fixingDates[_fixingDates.length - 1], position, _expiryIntervals[T]);
            adjustedRate = Math.multSigned(int64(proRata), rate);
        }

        // If the position was pending to be accounted, the fixingIndex0 should be equal 
        // to _fixings last index + 1 <=> _fixings.length
        bool positionIsNextFixing = position.startDate > _fixingDates[_fixingDates.length - 1];

        if (position.longShort == LongShort.Long) {
            if (positionIsNextFixing) {
                _longNotionalsForNextFixing[T] -= amount;
            } else {
                _longPositionsByTerm[T] -= amount;
                TotalLongPositions -= amount;
            }
        } else {
            if (positionIsNextFixing) {
                _shortNotionalsForNextFixing[T] -= amount;
            } else {
                _shortPositionsByTerm[T] -= amount;
                TotalShortPositions -= amount;
            }
        }
    }

    /*******************
     * Private Methods *
     *******************/
    function transferShortToLong(uint8 index, uint64 transferFromShortRatio, uint64 transferToLongRatio) private {
        uint192 totalLong = uint192(_longPositionsByTerm[index]);
        uint192 totalShort = uint192(_shortPositionsByTerm[index]);

        uint128 shortTransferAmt = uint128((totalShort * transferFromShortRatio) >> 32);
        uint128 longTransferAmt = uint128((totalLong * transferToLongRatio) >> 32);

        // We remove amount from the short side
        _shortPositionsByTerm[index] -= shortTransferAmt;
        TotalShortPositions -= shortTransferAmt;

        // We transfer amount to the long side
        _longPositionsByTerm[index] += longTransferAmt;
        TotalLongPositions += longTransferAmt;
    }

    function transferLongToShort(uint8 index, uint64 transferFromLongRatio, uint64 transferToShortRatio) private {
        uint192 totalLong = uint192(_longPositionsByTerm[index]);
        uint192 totalShort = uint192(_shortPositionsByTerm[index]);

        uint128 longTransferAmt = uint128((totalLong * transferFromLongRatio) >> 32);
        uint128 shortTransferAmt = uint128((totalShort * transferToShortRatio) >> 32);

        // We remove amount from the long side
        _longPositionsByTerm[index] -= longTransferAmt;
        TotalLongPositions -= longTransferAmt;

        // We transfer amount to the short side
        _shortPositionsByTerm[index] += shortTransferAmt;
        TotalShortPositions += shortTransferAmt;
    }
}