// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../enums.sol";
import "../interfaces/iopeninterest.sol";
import "../libraries/utils.sol";
import "../structures/openinterest.sol";

contract OpenInterests is IOpenInterest {
    /*****************
     * The modifiers *
     *****************/
    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    modifier isOpened() {
        require(block.timestamp < Maturity);
        _;
    }

    modifier isMatured() {
        require(block.timestamp >= Maturity);
        _;
    }

    modifier hasBeenFixed() {
        require(_hasBeenFixed);
        _;
    }

    /// @notice The address of the pool owning the open interest
    address private _owner;

    /// @notice The related token
    address private _token;

    /// @notice True if the fixing has been defined
    bool private _hasBeenFixed;

    /********************
     * Public variables *
     ********************/
    /// @notice The strike tick -> indicates how strikes are computed
    uint40 public StrikeTick;

    /// @notice The maturity of the options
    uint public Maturity;

    /// @notice The value of the underlying at maturity
    uint64 public Fixing;

    /******************************************
     * The variables to access open interests *
     ******************************************/
    /// @notice The open interests for the calls
    mapping(uint40 => uint256) private _callsTotalOpenInterests;
    mapping(uint40 => OpenInterest[]) private _callsOpenInterestsByStrikes;
    uint40[] private _callStrikes;

    mapping(address => uint40[]) private _callStrikesByUser;
    mapping(address => uint40) private _numberCallOpenInterestsByUser;
    mapping(address => mapping(uint40 => uint32[])) private _callsOpenInterestIndicesByUser;

    /// @notice The open interests for the puts
    mapping(uint40 => uint256) private _putsTotalOpenInterests;
    mapping(uint40 => OpenInterest[]) private _putsOpenInterestsByStrikes;
    uint40[] private _putStrikes;

    mapping(address => uint40[]) private _putStrikesByUser;
    mapping(address => uint40) private _numberPutOpenInterestsByUser;
    mapping(address => mapping(uint40 => uint32[])) private _putsOpenInterestIndicesByUser;

    constructor(address owner, address token, uint16 strikeTick, uint maturity) {
        _owner = owner;
        _token = token;
        _hasBeenFixed = false;
        StrikeTick = uint40(strikeTick);
        Maturity = maturity;
    }

    /// @notice Adds a new open interest
    function addOpenInterest(address buyer, address seller, uint256 quantity, uint40 strike, uint64 premium, OptionTypes optionType) external onlyOwner isOpened {
        // We recompute strikes to make sure that there will be no rounding issues
        strike = uint40(strike / StrikeTick) * StrikeTick;
        uint32 newIndex = 0;

        if (optionType == OptionTypes.Call) {
            newIndex = uint32(_callsOpenInterestsByStrikes[strike].length);
            Utils.addStrikeToList(_callStrikes, strike);
            
            Utils.addStrikeToList(_callStrikesByUser[buyer], strike);
            _callsOpenInterestIndicesByUser[buyer][strike].push(newIndex);
            _numberCallOpenInterestsByUser[buyer]++;
            Utils.addStrikeToList(_callStrikesByUser[seller], strike);
            _callsOpenInterestIndicesByUser[seller][strike].push(newIndex);
            _numberCallOpenInterestsByUser[seller]++;

            _callsOpenInterestsByStrikes[strike].push(OpenInterest(buyer, seller, strike, quantity, premium));
            _callsTotalOpenInterests[strike] += quantity;
        } else {
            newIndex = uint32(_putsOpenInterestsByStrikes[strike].length);
            Utils.addStrikeToList(_putStrikes, strike);

            Utils.addStrikeToList(_putStrikesByUser[buyer], strike);
            _putsOpenInterestIndicesByUser[buyer][strike].push(newIndex);
            _numberPutOpenInterestsByUser[buyer]++;
            Utils.addStrikeToList(_putStrikesByUser[seller], strike);
            _putsOpenInterestIndicesByUser[seller][strike].push(newIndex);
            _numberPutOpenInterestsByUser[seller]++;

            _putsOpenInterestsByStrikes[strike].push(OpenInterest(buyer, seller, strike, quantity, premium));
            _putsTotalOpenInterests[strike] += quantity;
        }
    }

    /// @notice Gets the total open interests by strikes, for calls and puts
    function getTotalOpenInterests() external view onlyOwner returns(uint40[] memory callStrikes, uint256[] memory callQuantities, uint40[] memory putStrikes,
     uint256[] memory putQuantities) {
        callStrikes = new uint40[](_callStrikes.length);
        callQuantities = new uint256[](_callStrikes.length);

        for (uint32 ncs = 0; ncs < _callStrikes.length; ncs++) {
            callStrikes[ncs] = _callStrikes[ncs];
            callQuantities[ncs] = _callsTotalOpenInterests[_callStrikes[ncs]];
        }

        putStrikes = new uint40[](_putStrikes.length);
        putQuantities = new uint256[](_putStrikes.length);

        for (uint32 nps = 0; nps < _putStrikes.length; nps++) {
            callStrikes[nps] = _putStrikes[nps];
            callQuantities[nps] = _putsTotalOpenInterests[_putStrikes[nps]];
        }
     }

    /// @notice Gets the open interest for a user
    function getOpenInterests() external view returns(OpenInterest[] memory calls, OpenInterest[] memory puts) {
        return _getOpenInterestsForUser(msg.sender);
    }

    /// @notice Gets the open interest for a user
    function getOpenInterestsForUser(address user) external view onlyOwner returns(OpenInterest[] memory calls, OpenInterest[] memory puts) {
        return _getOpenInterestsForUser(user);
    }

    function setFixing(uint64 fixing) external isMatured onlyOwner {
        Fixing = fixing;
        _hasBeenFixed = true;
    } 

    function solveOpenInterests() external hasBeenFixed returns(int256 pnl) {

    }

    /*******************
     * Private Methods *
     *******************/
    function _getOpenInterestsForUser(address user) private view returns(OpenInterest[] memory calls, OpenInterest[] memory puts) {
        calls = new OpenInterest[](_numberCallOpenInterestsByUser[user]);
        puts = new OpenInterest[](_numberPutOpenInterestsByUser[user]);

        uint32 i = 0;
        uint32 j = 0;
        uint40 count = 0;
        uint40 strike = 0;

        for (i = 0; i < _callStrikesByUser[user].length; i++) {
            strike = _callStrikesByUser[user][i];

            for (j = 0; j < _callsOpenInterestIndicesByUser[user][strike].length; j++) {
                calls[count] = _callsOpenInterestsByStrikes[strike][_callsOpenInterestIndicesByUser[user][strike][j]];
            }
        }

        for (i = 0; i < _putStrikesByUser[user].length; i++) {
            strike = _putStrikesByUser[user][i];

            for (j = 0; j < _putsOpenInterestIndicesByUser[user][strike].length; j++) {
                puts[count] = _putsOpenInterestsByStrikes[strike][_putsOpenInterestIndicesByUser[user][strike][j]];
            }
        }
    }
}