// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./fixingmanager.sol";
import "../enums.sol";
import "../interfaces/ierc20.sol";
import "../libraries/math.sol";
import "../libraries/safemath.sol";
import "../libraries/utils.sol";
import "../structures/position.sol";

abstract contract XMMPool is FixingManager {
    /**********
     * Events *
     **********/
    event Deposit(address indexed from, uint indexed timestamp, Position position);
    event PositionReduced(address indexed from, uint indexed timestamp, uint128 amount);
     
    event FeeChanged(uint indexed timestamp, uint8 oldFee, uint8 newFee);
    event PenaltyChanged(uint indexed timestamp, uint8 oldPenalty, uint8 newPenalty);

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

    modifier isLeveragePossible(Leverage leverage) {
        require(leverage == Leverage.One || LeverageIsActive, "No Leverage");
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

    /// @notice Gets the leverage status
    bool public LeverageIsActive;

    /// @notice The daily fee charged on the position
    // The fee is expressed in percent of a basis point
    uint8 public Fee;

    /// @notice The total amount of long positions, by leverage index
    mapping(uint8 => uint128) internal TotalLongPositions;

    /// @notice The total amount of short positions, by leverage index
    mapping(uint8 => uint128) internal  TotalShortPositions;
    
    /***************
     * Constructor *
     ***************/
    /// @param minDeposit The minimum deposit expressed in unit of poolToken; e.g. 10 for 10 poolToken minimum deposit
    constructor(address owner, address compensationToken, uint8 poolTokenDecimals, uint8 compensationTokenDecimals, Terms term, uint8 fee, uint8 penalty,
     uint64 minDeposit, uint8 minWithdrawalRatio) FixingManager(owner, compensationToken, compensationTokenDecimals, term) {
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
    /// @notice Changes the leverage status
    function changeLeverageStatus(bool status) external onlyOwner {
        LeverageIsActive = status;
    }

    function changeMinimumDeposit(uint64 minDeposit) external onlyOwner {
        MinDeposit = uint128(minDeposit) * uint128(10 ** _poolTokenDecimals);
    }

    /// @notice Gets the total accumulated fee
    function getAccumulatedFee() external view onlyOwner() returns(uint128) {
        return _accumulatedFee;
    }
    
    /// @notice Gets the total long and short positions for a given leverage factor
    function getPoolPendingPositions(Leverage leverage) external view returns(uint128 long, uint128 short) {
        uint8 lev = uint8(leverage);
        return (_longAmountForNextFixing[lev], _shortAmountForNextFixing[lev]);
    }

    /// @notice Gets the total long and short positions for a given leverage factor
    function getPoolPositions(Leverage leverage) external view returns(uint128 long, uint128 short) {
        uint8 lev = uint8(leverage);
        return (TotalLongPositions[lev], TotalShortPositions[lev]);
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

    /// @notice Creates a position on behaf of a user; e.g. if user transfers coin directly to the pool, pool owner
    //          can write the position
    /// @param amount   The amount of the position, inclusive of the fee -> if a client transfers 100 tokens, and the fee is 1 token
    //                  amount = 100 and fee = 1
    function createPositionForUser(LongShort longShort, Leverage leverage, uint128 amount, uint128 fee, address user) external onlyOwner {
        amount = SafeMath.sub128(amount, fee);
        uint timestamp = Utils.getTimeStamp(block.timestamp, _fixings[_fixings.length - 1].timestamp, _currentFixingUpdateInterval);
        
        writeDeposit(user, _fixings.length - 1, timestamp, longShort, amount, fee, leverage);
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

    /// @notice Sets whether the PenaltyFee will apply to users offsetting position before maturity
    function setApplyPenaltyFee(bool status) external onlyOwner {
        ApplyPenaltyFee = status;
    }

    /********************
     * Internal Methods *
     ********************/
    function getExistingPosition(address user, uint fixingIndex, LongShort longShort, Leverage leverage) internal view returns(bool, uint32) {
        Position[] storage positions = _positions[user];

        for (uint32 i = 0; i < positions.length; i++) {
            Position storage position = positions[i];
            if (position.longShort == longShort && position.leverage == leverage && position.fixingIndex0 == fixingIndex) return (true, i);
        }

        return (false, uint32(positions.length));
    }

    function writeDeposit(address user, uint lastFixingIndex, uint timestamp, LongShort longShort, uint128 amount, uint128 minFeePaid, Leverage leverage) internal {
        uint8 lev = uint8(leverage);
        bool isNextFixing = false;

        // If position is opened after mid update interval, the next fixing is used
        if (block.timestamp > timestamp + _currentMidFixingInterval) {
            timestamp += _currentFixingUpdateInterval;
            lastFixingIndex++;
            isNextFixing = true;
        }

        // We check if a user already has a position similar to this new order
        // Positions are equal when side, leverage and fixingIndex are the same
        (bool hasPosition, uint32 positionIndex) = getExistingPosition(user, lastFixingIndex, longShort, leverage);

        // If user already has a position which is equivalent to the current order
        // we just update the existing position
        if (hasPosition) {
            Position storage position = _positions[user][positionIndex];
            position.amount = SafeMath.add128(position.amount, amount);
            position.minFeePaid = SafeMath.add128(position.minFeePaid, minFeePaid);

            emit Deposit(user, block.timestamp, position);
        } else {
            Position memory position = Position(positionIndex, longShort, leverage, lastFixingIndex, timestamp, timestamp + _expiryInterval, amount, minFeePaid);
            _positions[user].push(position);

            emit Deposit(user, block.timestamp, position);
        }
           
        if (longShort == LongShort.Long) {
            // If the next fixing is used, the amount cannot be added to the current positions
            // The amount is pending to be added; when we update the fixing, we will add the pending positions
            if (isNextFixing) { 
                _longAmountForNextFixing[lev] = SafeMath.add128(_longAmountForNextFixing[lev], amount); 
            } else { 
                TotalLongPositions[lev] = SafeMath.add128(TotalLongPositions[lev], amount); 
                }
        } else {
            // If the next fixing is used, the amount cannot be added to the current positions
            // The amount is pending to be added; when we update the fixing, we will add the pending positions
            if (isNextFixing) { 
                _shortAmountForNextFixing[lev] = SafeMath.add128(_shortAmountForNextFixing[lev], amount);
            } else {
                TotalShortPositions[lev] = SafeMath.add128(TotalShortPositions[lev], amount);
            }
        }

        if (!isNextFixing) setRatios();
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

    /// @notice Returns the penalty amount
    function applyPenalty(uint128 amount) internal view returns(uint128) {
        return uint128((uint136(amount) * Penalty) / 1_000_000);
    }

    /****************************************
     * FixingManager Methods Implementation *
     ****************************************/
    function incorporateNextNotionals() internal override {
        for (uint8 i = 0; i < 6; i++) {
            TotalLongPositions[i] = SafeMath.sub128(TotalLongPositions[i], _longAmountForNextFixing[i]);
            TotalShortPositions[i] = SafeMath.sub128(TotalShortPositions[i], _shortAmountForNextFixing[i]);
            _longAmountForNextFixing[i] = 0;
            _shortAmountForNextFixing[i] = 0;
        }
    }

    function computeFactors(uint64 spotAtPeriodStart, uint64 spotAtPeriodEnd, uint64 premiumAtPeriodEnd) internal view override
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

    function executeMarginCall(uint64 prevSpot, Fixing memory lastFixing) internal override {
        (int64[] memory longRateFactors, int64[] memory shortRateFactors) = computeFactors(prevSpot, lastFixing.spot, lastFixing.premium);

        transfer(longRateFactors, shortRateFactors);

        for (uint8 i = 0; i < 6; i++) {
            _longRateIndices[i].push(Math.addSigned(_longRateIndices[i][_longRateIndices[i].length - 1], longRateFactors[i]));
            _shortRateIndices[i].push(Math.addSigned(_shortRateIndices[i][_shortRateIndices[i].length - 1], shortRateFactors[i]));
        }
    }

    function transfer(int64[] memory longRateFactors, int64[] memory shortRateFactors) internal override {
        for (uint8 i = 0; i < 6; i++) {
            // If longRateFactor is negative, long pays short
            // longRateFactor is equal to the premium accrual
            if (longRateFactors[i] < 0)  { transferLongToShort(i, uint64(-longRateFactors[i])); }
            // else, shortRateFactor is negative and equal to the accrued premium
            else { transferShortToLong(i, uint64(-shortRateFactors[i])); }
        }
    }

    /********************
     * Internal Methods *
     ********************/
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

    /// @notice Adjusts the rate of the position, updates the amounts and returns the compensation amount, if any
    function checkPosition(Position storage position, uint128 amount, int64 rate) internal returns(int64 adjustedRate, uint128 compensationAmt) {
        compensationAmt = 0;
        adjustedRate = rate;
        uint8 lev = uint8(position.leverage);

        // If rate is positive, only a pro-rata interest is paid
            // If rate is negative, msg.sender shall pay the full amount due
        if (rate > 0) {
            uint64 proRata = Utils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _currentFixingUpdateInterval), position, _expiryInterval);
            adjustedRate = Math.multSigned(int64(proRata), rate);
        }
        else if (isCompensable(position.longShort)) {
            compensationAmt = getCompensationAmount(position.amount, rate, _poolTokenDecimals);
        }

        // If the position was pending to be accounted, the fixingIndex0 should be equal 
        // to _fixings last index + 1 <=> _fixings.length
        bool positionIsNextFixing = position.fixingIndex0 == _fixings.length;

        if (position.longShort == LongShort.Long) {
            if (positionIsNextFixing) {
                _longAmountForNextFixing[lev] = SafeMath.sub128(_longAmountForNextFixing[lev], amount);
            } else {
                TotalLongPositions[lev] = SafeMath.sub128(TotalLongPositions[lev], amount);
            }
        } else {
            if (positionIsNextFixing) {
                _shortAmountForNextFixing[lev] = SafeMath.sub128(_shortAmountForNextFixing[lev], amount);
            } else {
                TotalShortPositions[lev] = SafeMath.sub128(TotalShortPositions[lev], amount);
            }
        }

        if (!positionIsNextFixing) setRatios();
    }

    /*******************
     * Private Methods *
     *******************/
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
}