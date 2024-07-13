// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ierc20.sol";
import "./interfaces/ixmmpool.sol";
import "./libraries/math.sol";
import "./libraries/safemath.sol";
import "./libraries/utils.sol";
import "./structures/fixing.sol";
import "./structures/position.sol";
import "./enums.sol";

contract XMMPool is IXMMPool {
    /**********
     * Events *
     **********/
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
    uint private _expiryInterval;
    int64 private _expiryYearFraction;
    int64 private _acrualYF;
    
    uint private _lastFixingIndex;

    // The positions by depositors
    mapping(address => Position[]) internal _positions;

    // Public properties
    /// @notice The start date of the XMM
    uint public StartDate;

    /// @notice The Term of the XMM
    Terms public Term;

    /// @notice The token which managed by the XMM
    address public Token;

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
    constructor(address token, uint8 decimals, Terms term, uint64 minDeposit) {
        Owner = msg.sender;
        Token = token;
        _decimals = decimals;
        Term = term;
        MinDeposit = (uint128(minDeposit) * uint128(10 ** decimals)) / uint128(2 ** 32);

        (_fixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);
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
    function getFixings() external view returns(Fixing[] memory) {
        return Fixings;
    }

    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner) external {
        if (msg.sender == Owner) Owner = newOwner;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param amount The amount to be deposited
    function deposit(LongShort longShort, uint128 amount) external isActive hasMinDeposit(amount) {
        (, bytes memory res) = Token.call(abi.encodeWithSelector(IERC20.balanceOf.selector, msg.sender));
        (bool success, bytes memory allowanceBytes) = Token.call(abi.encodeWithSelector(IERC20.allowance.selector, msg.sender, address(this)));

        if (success) {
            uint256 balance = abi.decode(res, (uint256));
            uint256 allowance = abi.decode(allowanceBytes, (uint256));

            require(balance >= amount, "Insufficient balance");
            require(allowance >= amount, "Insufficient allowance");

            (success, res) = Token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(this), uint256(amount)));

            if (success && abi.decode(res, (bool))) {
                uint32 positionIndex = uint32(_positions[msg.sender].length);
                int64 index0 = (longShort == LongShort.Long ? _longRateIndex[_lastFixingIndex] : _shortRateIndex[_lastFixingIndex]);
                uint timestamp = Fixings[_lastFixingIndex].timestamp;

                Position memory position = Position(positionIndex, longShort, index0, timestamp, timestamp + _expiryInterval, amount);
                _positions[msg.sender].push(position);
                
                if (longShort == LongShort.Long) {
                    TotalLongPositions = SafeMath.SafeAdd128(TotalLongPositions, amount);
                } else {
                    TotalShortPositions = SafeMath.SafeAdd128(TotalShortPositions, amount);
                }

                getRatios();

                emit Deposit(msg.sender, block.timestamp, position);
            }
        }
    }

    /// @notice Closes all the positions held by a user.
    function closeAllPositions() external {
        if (_positions[msg.sender].length > 0) {
            for (uint32 i = 0; i < _positions[msg.sender].length; i++) this.closePosition(i);
        }
    }

    /// @notice Closes a position
    function closePosition(uint32 positionIndex) external {
        if (_positions[msg.sender].length > positionIndex) {
            this.reducePosition(positionIndex, _positions[msg.sender][positionIndex].amount);
        }
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) external {
        if (_positions[msg.sender].length > positionIndex) {
            Position storage position = _positions[msg.sender][positionIndex];
            (LongShort ls, uint32 index, uint128 finalAmount, bool toDelete) = Utils.reducePosition(position, amount);

            int64 proRata = Utils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _fixingUpdateInterval), position, _expiryInterval);
            int64 rate = getRate(ls, proRata, position.index0);

            if (ls == LongShort.Long) {
                TotalLongPositions = SafeMath.SafeSub128(TotalLongPositions, finalAmount);
            } else {
                TotalShortPositions = SafeMath.SafeSub128(TotalShortPositions, finalAmount);
            }

            getRatios();

            if (toDelete) Utils.removePositionFromArray(index, _positions[msg.sender]);

            finalAmount = uint128(int128(((int256(int128(finalAmount)) << 32) * rate) >> 32));
            (bool success, ) = Token.delegatecall(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, finalAmount));

            if (success) emit PositionReduced(msg.sender, block.timestamp, finalAmount);
        }
    }

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
        
        Fixing memory fixing = Fixing(firstTimestamp, spot, strike, volatility, optionPremium);

        _lastFixingIndex = 0;
        Fixings.push(fixing);

        IsActivated = true;
    }

    /// @notice Sets the latest fixing for the XMM
    function setFixing(uint64 spot, uint64 strike, uint64 volatility, int64 optionPremium) external onlyOwner {
        Fixing storage lastFixing = Fixings[_lastFixingIndex];
        uint nextFixingTimestamp = Utils.getTimeStamp(block.timestamp, lastFixing.timestamp, _fixingUpdateInterval);
        
        // Next fixing timestamp must be after the last fixing
        if (nextFixingTimestamp < lastFixing.timestamp + _fixingUpdateInterval) return;
        Fixing memory fixing = Fixing(nextFixingTimestamp, spot, strike, volatility, optionPremium);
        executeMarginCalls(lastFixing.spot, lastFixing.timestamp, fixing);
        
        _lastFixingIndex += 1;
        if (_lastFixingIndex == Utils.MAX_NUMBER_FIXINGS) _lastFixingIndex = 0;
        if (Fixings.length < Utils.MAX_NUMBER_FIXINGS) Fixings.push(fixing);
        else Fixings[_lastFixingIndex] = fixing;
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
        int64 currentIndex = longShort == LongShort.Long ? _longRateIndex[_lastFixingIndex] : _shortRateIndex[_lastFixingIndex];
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