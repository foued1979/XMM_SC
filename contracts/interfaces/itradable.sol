// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface ITradable {
    event Deposit(uint indexed timestamp, address indexed from, uint256 amount);
    event Changed(uint indexed timestamp, address indexed beneficiary, uint256 amount);

    /// @notice Sets the change authorization status
    function setChangeAuthorization(bool status) external;

    /// @notice Updates the exchange rate between ETH and the Token
    function updateExchangeRate(uint64 exchangeRate) external;

    /// @notice Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256);

    /// @notice Enables a user to deposit ETH and receive Tokens in exchange
    /// The conversion rate applies at a fixed rate, updated by Owner
    function depositEther(uint256 maxGas) external payable returns(uint256);

    /// @notice Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external payable returns(bool);

    /// @notice Enables the Owner to buy back tokens from a user, in exchange of ETH
    /// and at a specified rate
    /// @param from The beneficiary
    /// @param amountToken The amount of tokens
    /// @param rate The conversion rate
    function buyBack(address payable from, uint128 amountToken, uint64 rate) external payable returns(bool);
}