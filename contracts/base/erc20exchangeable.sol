// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { IERC20 } from "../interfaces/ierc20.sol";
import { IExchangeable } from "../interfaces/iexchangeable.sol";

abstract contract ERC20Exchangeable is IExchangeable {
    /*************
     * Modifiers *
     *************/
     modifier _onlyOwner {
        require(msg.sender == _owner, "Err0");
        _;
    }

    modifier ethDepositIsAllowed {
        require(ETHDepositIsAllowed, "Err1");
        _;
    }

    modifier ethExchangeIsAllowed {
        require(ETHExchangeIsAllowed && EthExchangeRate != 0, "Err2");
        _;
    }

    modifier exchangeIsAllowedForToken(address token) {
        require(_tokenIsApproved[token] && _exchangeIsAllowed[token] && _exchangeRates[token] != 0, "Err3");
        _;
    }

    modifier tokenIsApproved(address token) {
        require(_tokenIsApproved[token], "Err4");
        _;
    }

     /**************
     * Properties *
     **************/
     // Private Properties
     address private _owner;

    // Public properties linked to IExchangeable
    // The exchange rate represents a real number with 4 digits precision
    bool public ETHExchangeIsAllowed;
    bool public ETHDepositIsAllowed;
    uint64 public EthExchangeRate;
    uint16 internal _precision = 10_000;

    // Parameters to manage other token exchanges
    mapping(address tokenAddress => bool) internal _tokenIsApproved;
    mapping(address tokenAddress => uint64) internal _exchangeRates;
    mapping(address tokenAddress => bool) internal _exchangeIsAllowed;

    // Other public Properties
    address[] public ApprovedTokens;
    mapping(address tokenAddress => uint8) internal _approvedTokenDecimals;

    /***************
     * Constructor *
     ***************/
    constructor(address owner_) {
        _owner = owner_;
        ETHDepositIsAllowed = false;
        ETHExchangeIsAllowed = false;
    }

    /// @dev Sets the change authorization status for ETH to false
    function removeETHExchangeAuthorization() external _onlyOwner {
        ETHExchangeIsAllowed = false;
    }

    /// @dev Sets the change authorization status for a token to false
    function removeExchangeAuthorizationForToken(address tokenToBeReceived) external _onlyOwner tokenIsApproved(tokenToBeReceived) {
        _exchangeIsAllowed[tokenToBeReceived] = false;
    }

    /// @dev Sets whether the deposit of ETH against token is allowed or not
    //          The exchange rate is expressed in pips
    function setETHDepositExchangeRate(uint64 exchangeRate) external _onlyOwner {
        EthExchangeRate = exchangeRate;
        ETHDepositIsAllowed = true;
    }

    /// @dev Sets the ETH deposit authorization to false
    function removeETHDepositAuthorization() external _onlyOwner {
        ETHDepositIsAllowed = false;
    }

    /// @dev Updates the exchange rate between ETH and the Token
    //          The exchange rate is expressed in pips
    function updateETHExchangeRate(uint64 exchangeRate) external _onlyOwner {
        EthExchangeRate = exchangeRate;
        ETHExchangeIsAllowed = true;
    }

    /// @dev Updates the exchange rate between a token and our Token
    /// @param  tokenToBeReceived The token to be received in exchange of our Token
    /// @param  exchangeRate The exchange rate, with 4 digits precision (in pips)
    function updateTokenExchangeRate(address tokenToBeReceived, uint64 exchangeRate) external _onlyOwner tokenIsApproved(tokenToBeReceived) {
        _exchangeRates[tokenToBeReceived] = exchangeRate;
        _exchangeIsAllowed[tokenToBeReceived] = true;
    }

    /// @dev Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256) {
        return address(this).balance;
    }

    /// @dev Returns the latest exchange rate associated to the token to be received
    /// @return Whether the exchange is authorized and the latest exchange rate
    function getExchangeInfoForToken(address tokenToBeReceived) external view tokenIsApproved(tokenToBeReceived) returns(bool, uint64) {
        return (_exchangeIsAllowed[tokenToBeReceived], _exchangeRates[tokenToBeReceived]);
    }

    /// @dev Returns the available quantity of a token to be exchanged
    function getAvailableQuantityOfToken(address tokenToBeReceived) public tokenIsApproved(tokenToBeReceived) returns(uint256) {
        (bool success , bytes memory res) = tokenToBeReceived.call(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));

        if (success) return abi.decode(res, (uint256));
        return 0;
    }

    /// @dev Adds a token which can be traded against our Token
    function addApprovedToken(address token, uint8 decimals) external _onlyOwner {
        require(decimals <= 18, "Err10");
        if (_tokenIsApproved[token]) return;

        _tokenIsApproved[token] = true;
        _exchangeIsAllowed[token] = false;

        ApprovedTokens.push(token);
        _approvedTokenDecimals[token] = decimals;
    }

    /// @dev Gets approved tokens
    function getApprovedTokens() external view returns(address[] memory) {
        return ApprovedTokens;
    }
}