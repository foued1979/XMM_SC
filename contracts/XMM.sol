// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ierc20.sol";
import "./interfaces/ixmm.sol";
import "./libraries/financial.sol";
import "./libraries/math.sol";
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
        require(msg.sender == _owner);
        _;
    }

    /***********************
     * Contract Properties *
     ***********************/
    // Private properties
    address private _owner;
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

    /// @notice The list of fixings
    Fixing[] public Fixings;

    /// @notice The rate index
    uint64[] public RateIndex;

    /// @notice The total amount of long positions
    uint256 public TotalLongPositions;

    /// @notice The total amount of short positions
    uint256 public TotalShortPositions;

    /*************
     * Functions *
     *************/
    constructor(address token, Terms term, Fixing memory fixing) {
        _owner = msg.sender;
        Token = token;
        Term = term;
        StartDate = Utils.getTimeStamp(block.timestamp);

        (_fixingUpdateInterval, _expiryInterval, _expiryYearFraction) = Utils.getTermInformation(term);
        _acrualYF = Math.div(int64(_fixingUpdateInterval * (2 ** 32)), int64(_expiryInterval * (2 ** 32)));

        _lastFixing = 0;
        Fixings.push(fixing);
        RateIndex[0] = 1 << 32;
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
    function deposit(LongShort longShort, uint128 amount) external {
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
                    TotalLongPositions += amount;
                } else {
                    TotalShortPositions += amount;
                }

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
    function reducePosition(uint32 positionIndex, uint256 amount) external {
        if (_positions[msg.sender].length > positionIndex) {
            (LongShort ls, uint32 index, uint256 finalAmount, bool toDelete) = Utils.reducePosition(_positions[msg.sender][positionIndex], amount);

            if (ls == LongShort.Long) {
                TotalLongPositions -= finalAmount;
            } else {
                TotalShortPositions -= finalAmount;
            }

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

        int64 spotPerf = Math.sub(lastFixing.spot, prevFixing.spot);
        
        if (spotPerf > 0) {
            
        } else {

        }
        
    }

    function transferShortToLong(int64 netPremiumPerf) private {

    }
}