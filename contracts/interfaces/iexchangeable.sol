// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IExchangeable {
    event Deposited(uint indexed timestamp, address indexed from, uint256 amountETH, uint256 amountToken);
    event ChangedBack(uint indexed timestamp, address indexed beneficiary, uint256 amountTokens);
    event ChangedBackFor(uint indexed timestamp, address indexed beneficiary, address tokenReceived, uint256 amount);
    event Withdrawn(uint indexed timestamp, address indexed from, uint256 amount);    

    /// @notice Sets the change authorization status
    function setETHExchangeAuthorization(bool status) external;

    /// @notice Sets the change authorization status for a token
    function setChangeAuthorization(address tokenToBeReceived, bool status) external;

    /// @notice Updates the exchange rate between ETH and the Token
    function updateETHExchangeRate(uint64 exchangeRate) external;

    /// @notice Updates the exchange rate between a token and our Token
    /// @param  tokenToBeReceived The token to be received in exchange of our Token
    /// @param  exchangeRate The exchange rate
    function updateExchangeRate(address tokenToBeReceived, uint64 exchangeRate) external;

    /// @notice Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256);

    /// @notice Returns the available quantity of a token to be exchanged against our Token
    function getAvailableQuantityOfToken(address tokenToBeReceived) external returns(uint256);

    /// @notice Enables a user to deposit ETH and receive Tokens in exchange
    /// The conversion rate applies at a fixed rate, updated by Owner
    function depositEther() external payable returns(uint256);

    /// @notice Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external;

    /// @notice Enables a user to sell back an amount of Tokens against a preferred token
    /// if there is enough token available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    /// @param tokenToBeReceived The address of the token to be exchanged for
    function sellBackAgainst(uint128 amountToken, address tokenToBeReceived) external;

    /// @notice Enables the Owner to buy back tokens from a user, in exchange of ETH
    /// and at a specified rate
    /// @param from The beneficiary
    /// @param amountToken The amount of tokens
    /// @param rate The conversion rate
    function buyBack(address payable from, uint128 amountToken, uint64 rate) external;
}