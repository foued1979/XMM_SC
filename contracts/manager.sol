// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ixmmpool.sol";
import "./libraries/utils.sol";
import "./enums.sol";
import "./xmmpool.sol";

contract Manager {
    /**********
     * Events *
     **********/
     event OwnerChanged(uint indexed timestamp, address previous, address current);
     event XMMCreated(uint indexed timestamp, address token, Terms term, address xmm);

    /*****************
     * The modifiers *
     *****************/
    modifier onlyOwner {
        require(msg.sender == Owner);
        _;
    }

    /**************
     * Properties *
     **************/
    // Public properties
    address public Owner;

    // Private properties
    mapping(address => address[7]) private _listOfXMMs;
    address[] private _registeredTokens;

    constructor(address owner) {
        Owner = owner;
    }

    function changeOwnership(address newOwner) external onlyOwner {
        Owner = newOwner;
        emit OwnerChanged(block.timestamp, msg.sender, newOwner);
    }

    function getXMMPools(address token) external view returns(address[7] memory) {
        return _listOfXMMs[token];
    }

    function getRegisteredTokens() external view returns(address[] memory) {
        return _registeredTokens;
    }

    /// @notice Creates a new XMM
    /// @param token The token to deposit
    /// @param term The term of the expected deposits
    function createXMMPool(address token, uint8 decimals, Terms term, uint64 minDeposit) external onlyOwner {
        require(_listOfXMMs[token][uint(term)] == address(0x0), "xmm pool already exists");

        if (!Utils.itemExistsInArray(token, _registeredTokens)) {
            _registeredTokens.push(token);
        }

        XMMPool newXMM = new XMMPool(token, decimals, term, minDeposit);
        address newXMMAddress = address(newXMM);
        _listOfXMMs[token][uint(term)] = newXMMAddress;
        emit XMMCreated(block.timestamp, token, term, newXMMAddress);
    }

    /// @notice Sets the first fixings for a token and activates the pools
    function setFirstFixings(address token, int64 spot, int64[7] memory strikes, int64[7] memory volatilities, int64[7] memory optionPremia) external onlyOwner {
        address[7] storage xmmPools = _listOfXMMs[token];

        for (uint8 i = 0; i < 7; i++) {
            if (address(xmmPools[i]) == address(0x0)) continue;
            IXMMPool(xmmPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
        }
    }

    /// @notice Sets the fixings for a token
    function setFixings(address token, int64 spot, int64[7] memory strikes, int64[7] memory volatilities, int64[7] memory optionPremia) external onlyOwner {
        address[7] storage xmmPools = _listOfXMMs[token];

        for (uint8 i = 0; i < 7; i++) {
            if (address(xmmPools[i]) == address(0x0)) continue;
            IXMMPool(xmmPools[i]).setFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
        }
    }
}