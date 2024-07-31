// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ixmmpool.sol";
import "./interfaces/ikyc.sol";
import "./libraries/utils.sol";
import "./enums.sol";
import "./pools/coinpool.sol";
import "./pools/coinkycpool.sol";

contract Manager {
    /**********
     * Events *
     **********/
     event OwnerChanged(uint indexed timestamp, address previous, address current);
     event PoolCreated(uint indexed timestamp, address token, Terms term, address xmm);
     event KYCPoolCreated(uint indexed timestamp, address token, Terms term, address xmm);

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
    address[7] private _listOfETHPools;
    address[7] private _listOfETHKYCPools;
    mapping(address => address[7]) private _listOfCoinPools;
    mapping(address => address[7]) private _listOfCoinKYCPools;

    address[] private _registeredTokensNonKYC;
    address[] private _registeredTokensKYC;

    constructor(address owner) {
        Owner = owner;
    }

    function changeOwnership(address newOwner) external onlyOwner {
        Owner = newOwner;
        emit OwnerChanged(block.timestamp, msg.sender, newOwner);
    }

    function getPools(address token) external view returns(address[7] memory) {
        return _listOfXMMs[token];
    }

    function getRegisteredTokens() external view returns(address[] memory) {
        return _registeredTokens;
    }

    /// @notice Sets the KYC status for a user on all KYC pools
    function setUserKYCStatus(address user, bool isKYC) external onlyOwner {
        for (uint i = 0; i < 7; i++) {
            IKYC(_listOfETHKYCPools[i]).updateKYCUserStatus(user, status);
        }

        for (uint i = 0; i < _registeredTokensKYC.length; i++) {
            address[7] storage kycPools = _listOfCoinKYCPools[_registeredTokensKYC[i]];

            for (uint j = 0; j < 7; j++) {
                IKYC(kycPools[j]).updateKYCUserStatus(user, status);
            }
        }
    }

    /// @notice Creates a new KYC XMM pool
    /// @param token The token to deposit
    /// @param term The term of the expected deposits
    function createKYCPool(address token, uint8 decimals, Terms term, uint64 minDeposit) external onlyOwner {
        require(_listOfCoinKYCPools[token][uint(term)] == address(0x0), "xmm pool already exists");

        if (!Utils.itemExistsInArray(token, _registeredTokensKYC)) {
            _registeredTokensKYC.push(token);
        }

        CoinKYCPool newXMM = new CoinKYCPool(token, decimals, term, minDeposit);
        address newXMMAddress = address(newXMM);
        _listOfCoinKYCPools[token][uint(term)] = newXMMAddress;
        emit KYCPoolCreated(block.timestamp, token, term, newXMMAddress);
    }

    /// @notice Creates a new XMM
    /// @param token The token to deposit
    /// @param term The term of the expected deposits
    function createPool(address token, uint8 decimals, Terms term, uint64 minDeposit) external onlyOwner {
        require(_listOfCoinPools[token][uint(term)] == address(0x0), "xmm pool already exists");

        if (!Utils.itemExistsInArray(token, _registeredTokensNonKYC)) {
            _registeredTokensNonKYC.push(token);
        }

        CoinPool newXMM = new CoinPool(token, decimals, term, minDeposit);
        address newXMMAddress = address(newXMM);
        _listOfCoinPools[token][uint(term)] = newXMMAddress;
        emit PoolCreated(block.timestamp, token, term, newXMMAddress);
    }

    /// @notice Sets the first fixings for a token and activates the pools
    function setFirstFixings(address token, uint64 spot, uint64[7] memory strikes, uint64[7] memory volatilities, int64[7] memory optionPremia) external onlyOwner {
        address[7] storage xmmPools = _listOfCoinPools[token];
        address[7] storage xmmKYCPools = _listOfCoinKYCPools[token];

        for (uint8 i = 0; i < 7; i++) {
            if (optionPremia[i] <= 0) continue;
            if (address(xmmPools[i]) != address(0x0)) IXMMPool(xmmPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
            if (address(xmmKYCPools[i]) != address(0x0)) IXMMPool(xmmKYCPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
        }
    }

    /// @notice Sets the first fixings for a token and activates the pools
    function setFirstETHFixings(uint64 spot, uint64[7] memory strikes, uint64[7] memory volatilities, int64[7] memory optionPremia) external onlyOwner {
        for (uint8 i = 0; i < 7; i++) {
            if (optionPremia[i] <= 0) continue;
            if (address(_listOfETHPools[i]) != address(0x0)) IXMMPool(_listOfETHPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
            if (address(_listOfETHKYCPools[i]) != address(0x0)) IXMMPool(_listOfETHKYCPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
        }
    }

    /// @notice Sets the fixings for a token
    function setFixings(address token, uint64 spot, uint64[7] memory strikes, uint64[7] memory volatilities, int64[7] memory optionPremia) external onlyOwner {
        address[7] storage xmmPools = _listOfCoinPools[token];
        address[7] storage xmmKYCPools = _listOfCoinKYCPools[token];

        for (uint8 i = 0; i < 7; i++) {
            if (optionPremia[i] <= 0) continue;
            if (address(xmmPools[i]) != address(0x0)) IXMMPool(xmmPools[i]).setFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
            if (address(xmmKYCPools[i]) != address(0x0)) IXMMPool(xmmKYCPools[i]).setFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
        }
    }

    /// @notice Sets the fixings for a token
    function setETHFixings(address token, uint64 spot, uint64[7] memory strikes, uint64[7] memory volatilities, int64[7] memory optionPremia) external onlyOwner {
        for (uint8 i = 0; i < 7; i++) {
            if (optionPremia[i] <= 0) continue;
            if (address(_listOfETHPools[i]) != address(0x0)) IXMMPool(_listOfETHPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
            if (address(_listOfETHKYCPools[i]) != address(0x0)) IXMMPool(_listOfETHKYCPools[i]).setFirstFixing(spot, strikes[i], volatilities[i], optionPremia[i]);
        }
    }
}