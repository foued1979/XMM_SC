// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ierc20.sol";
import "./interfaces/ixmm.sol";
import "./libraries/financial.sol";
import "./libraries/math.sol";
import "./libraries/safemath.sol";
import "./libraries/utils.sol";
import "./structures/fixing.sol";
import "./structures/position.sol";
import "./enums.sol";

contract XMM is IXMM {
    /**********
     * Events *
     **********/
     event Deposit(uint timestamp, address from, Position position);

    /*****************
     * The modifiers *
     *****************/
    modifier onlyOwner {
        require(msg.sender == _owner, "Only owner");
        _;
    }

    modifier hasMinDeposit(uint128 amount) {
        require(amount >= MinDeposit, "Min deposit");
        _;
    }

    /***********************
     * Contract Properties *
     ***********************/
    // Private properties
    address private _owner;

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
    uint64 public MinDeposit;

    /// @notice The list of fixings
    Fixing[] public Fixings;

    /// @notice The total amount of long positions
    uint128 public TotalLongPositions;
    uint128 private _marginCallLong;
    int64 private _longRatio;
    int64[] private _longIndex;

    /// @notice The total amount of short positions
    uint128 public TotalShortPositions;
    uint128 private _marginCallShort;
    int64 private _shortRatio;
    int64[] private _shortIndex;

    /*************
     * Functions *
     *************/
    constructor(address token, uint8 decimals, Terms term, uint64 minDeposit, Fixing memory fixing) {
        _owner = msg.sender;
        Token = token;
        _decimals = decimals;
        Term = term;
        MinDeposit = minDeposit;

        StartDate = Utils.getTimeStamp(block.timestamp);

        (_fixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);
        _acrualYF = Math.div(int64(_fixingUpdateInterval << 32), int64(_expiryInterval << 32));

        _lastFixing = 0;
        Fixings.push(fixing);
        _longIndex[0] = Math.One_32;
        _shortIndex[0] = Math.One_32;
    }

    /// @notice Gets the term of the XMM
    function getTerm() external view returns(Terms) {
        return Term;
    }

    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner) external {
        if (msg.sender == _owner) _owner = newOwner;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param amount The amount to be deposited
    function deposit(LongShort longShort, uint128 amount) external hasMinDeposit(amount) {
        (bool success, bytes memory res) = Token.call(abi.encodeWithSelector(IERC20.balanceOf.selector, msg.sender));

        if (success) {
            uint256 balance = abi.decode(res, (uint256));
            require(balance >= amount, "Insufficient balance");

            (success, res) = Token.call(abi.encodeWithSelector(IERC20.transfer.selector, address(this), uint256(amount)));

            if (success) {
                uint positionIndex = uint32(_positions[msg.sender].length);
                Fixing storage fixing = Fixings[Utils.getFixingIndex(block.timestamp, StartDate, _fixingUpdateInterval)];
                Position storage position = Position(positionIndex, longShort, fixing, fixing.timestamp + _expiryInterval, amount);
                _positions[msg.sender].push(position);
                
                if (longShort == LongShort.Long) {
                    TotalLongPositions = SafeMath.add(TotalLongPositions, amount);
                } else {
                    TotalShortPositions = SafeMath.add(TotalShortPositions, amount);
                }

                getRatios();

                emit Deposit(block.timestamp, msg.sender, position);
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
            (LongShort ls, uint32 index, uint128 finalAmount, bool toDelete) = Utils.reducePosition(_positions[msg.sender][positionIndex], amount);

            if (ls == LongShort.Long) {
                TotalLongPositions = SafeMath.sub(TotalLongPositions, finalAmount);
            } else {
                TotalShortPositions = SafeMath.sub(TotalShortPositions, finalAmount);
            }

            getRatios();
            if (toDelete) Utils.removePositionFromArray(index, _positions[msg.sender]);

            code if reduce => need to pay
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

    /// @notice Sets the latest fixing for the XMM
    function setFixing(address token, int64 spot, int64 strike, uint64 volatility, int64 discountRate) external onlyOwner {
        require(token == Token, "Wrong token");
        int64 optionPremium = FinancialLib.putPremium(spot, strike, volatility, _expiryYearFraction);
        Fixing memory fixing = Fixing(timestamp, spot, strike, volatility, optionPremium, discountRate);

        executeMarginCalls(Fixings[_lastFixingIndex].spot, fixing);
        
        _lastFixingIndex += 1;
        if (_lastFixingIndex == Utils.MAX_NUMBER_FIXINGS) _lastFixingIndex = 0;
        Fixings[_lastFixingIndex] = fixing;
    }

    function executeMarginCalls(uint64 prevSpot, Fixing memory lastFixing) private {
        
        int64 premiumPerf = Math.mult(lastFixing.premium, _acrualYF);
        int64 discountRatePerf = Math.mult(lastFixing.discountRate, Utils.ONE_DAY_YF);

        int64 spotPerf = Math.div(Math.sub(lastFixing.spot, prevFixing.spot), prevFixing.spot);
        if (spotPerf > 0) spotPerf = 0;
        
        int64 shortPerf = Math.add(spotPerf, discountRatePerf);
        int64 longPerf = Math.mult(_longRatio, Math.sub(premiumPerf, shortPerf));

        if (shortPerf < premiumPerf) {
            transferShortToLong(uint64(longPerf));
            shortPerf = Math.mult(_shortRatio, Math.sub(shortPerf, premiumPerf));
        } else {
            shortPerf = Math.mult(_shortRatio, Math.sub(shortPerf, premiumPerf));
            transferLongToShort(uint64(shortPerf));
        }
        
        int64 longRateFactor = Math.mult(_longIndex[_longIndex.length - 1], Math.add(Math.One_32, longPerf));
        int64 shortRateFactor = Math.mult(_shortIndex[_shortIndex.length - 1], Math.add(Math.One_32, shortPerf));

        _longIndex.push(longRateFactor);
        _shortIndex.push(shortRateFactor);
    }

    function transferShortToLong(uint64 netPerf) private {
        uint128 transfer = uint128(TotalShortPositions >> Math.max(int8(_decimals - 2), 0));
        transfer = uint128((transfer * netPerf) >> 32);

        if (_marginCallLong > transfer) {
            _marginCallLong = SafeMath.sub(_marginCallLong, transfer);
        } else {
            transfer = SafeMath.sub(transfer, _marginCallLong)
            _marginCallShort = SafeMath.add(_marginCallShort, transfer);
        }
    }

    function transferLongToShort(uint64 netPerf) private {
        uint128 transfer = uint128(TotalLongPositions >> Math.max(int8(_decimals - 2), 0));
        transfer = uint128((transfer * netPerf) >> 32);

        if (_marginCallShort > transfer) {
            _marginCallShort = SafeMath.sub(_marginCallShort, transfer);
        } else {
            transfer = SafeMath.sub(transfer, _marginCallShort)
            _marginCallLong = SafeMath.add(_marginCallLong, transfer);
        }
    }

    function getRatios() private {
        _longRatio = getLongRatio();
        _shortRatio = getShortRatio();
    }

    function getLongRatio() private pure return(int64) {
        uint256 short = uint256(TotalShortPositions) << 32;
        return int64(uint64(short / TotalLongPositions));
    }

    function getShortRatio() private pure returns(int64) {
        uint256 long = uint256(TotalLongPositions) << 32;
        return int64(uint64(long / TotalShortPositions));
    }
}