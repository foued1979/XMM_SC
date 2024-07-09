// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ixmm.sol";
import "./libraries/utils.sol";
import "./enums.sol";
import "./xmm.sol";

contract Manager {
    /**********
     * Events *
     **********/
     event OwnerChanged(uint indexed timestamp, address token, address previous, address current);
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
    }

    function changeOwnershipForAllTokens(address newOwner) external onlyOwner {
        for (uint i = 0; i < _registeredTokens.length; i++) {
            this.changeOwnershipForToken(_registeredTokens[i], newOwner);
        }

        this.changeOwnership(newOwner);
    }

    function changeOwnershipForToken(address token, address newOwner) external onlyOwner {
        for (uint j = 0; j < 7; j++) {
            IXMM(_listOfXMMs[token][j]).changeOwnership(newOwner);
        }

        emit OwnerChanged(block.timestamp, token, msg.sender, newOwner);
    }

    function getXMMPools(address token) external view returns(address[7] memory) {
        return _listOfXMMs[token];
    }

    /// @notice Creates a new XMM
    /// @param token The token to deposit
    /// @param term The term of the expected deposits
    function createXMMPool(address token, uint8 decimals, Terms term, uint64 minDeposit, Fixing memory fixing) external onlyOwner {
        require(_listOfXMMs[token][uint(term)] == address(0x0), "xmm already exists");

        if (!Utils.itemExistsInArray(token, _registeredTokens)) {
            _registeredTokens.push(token);
        }

        XMMPool newXMM = new XMMPool(token, decimals, term, minDeposit, fixing);
        address newXMMAddress = address(newXMM);
        _listOfXMMs[token][uint(term)] = newXMMAddress;
        emit XMMCreated(block.timestamp, token, term, newXMMAddress);
    }
}