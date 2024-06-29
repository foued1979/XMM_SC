// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IERC20 {
    /// @notice Returns the amount of tokens owned by account
    /// @param account The address of the account
    function balanceOf(address account) external view returns(uint256);

    /// @notice Transfers tokens
    /// @param to The recipient wallet
    /// @param amount The amount to be transferred
    // Throws Transfer event
    function transfer(address to, uint256 amount) external returns(bool);
}