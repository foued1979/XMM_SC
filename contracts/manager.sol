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
     event OwnerChanged(address previous, address current);
     event XMMCreated(uint timestamp, address token, Terms term, address xmm);

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
    mapping(address => address[6]) private _listOfXMMs;
    address[] private _registeredTokens;

    constructor() {
        Owner = msg.sender;
        emit OwnerChanged(address(0x0), msg.sender);
    }

    function changeOwnership(address newOwner) external onlyOwner returns(bool) {
        Owner = newOwner;

        for (uint i = 0; i < _registeredTokens.length; i++) {
            try _changeOwnership(newOwner, _listOfXMMs[_registeredTokens[i]]) returns(bool success) { }
            catch  { return false; } 
        }

        emit OwnerChanged(msg.sender, newOwner);
        return true;
    }

    /// @notice Creates a new XMM
    /// @param token The token to deposit
    /// @param term The term of the expected deposits
    function createXMM(address token, Terms term) external onlyOwner returns(address) {
        require(_listOfXMMs[token][term] == address(0x0), "xmm already exists");

        if (!Utils.itemExistsInArray(token, _registeredTokens)) {
            _registeredTokens.push(token);
        }

        address newXMM = new XMM(token, term);
        _listOfXMMs[token][term] = newXMM;
        emit XMMCreated(block.timestamp, token, term, newXMM);
        return newXMM;
    }

    function _changeOwnership(address newOwner, address[] xmms) private returns(bool) {
        for (uint j = 0; j < 6; j++) {
            IXMM(xmms[j]).changeOwnership(newOwner);
        }
    }
}