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

    constructor() {
        Owner = msg.sender;
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

    /// @notice Creates a new XMM
    /// @param token The token to deposit
    /// @param term The term of the expected deposits
    function createXMM(address token, uint8 decimals, Terms term, uint64 minDeposit, Fixing memory fixing) external onlyOwner returns(address) {
        require(_listOfXMMs[token][uint(term)] == address(0x0), "xmm already exists");

        if (!Utils.itemExistsInArray(token, _registeredTokens)) {
            _registeredTokens.push(token);
        }

        address newXMM = address(new XMM(token, decimals, term, minDeposit, fixing));
        _listOfXMMs[token][uint(term)] = newXMM;
        emit XMMCreated(block.timestamp, token, term, newXMM);
        return newXMM;
    }
}