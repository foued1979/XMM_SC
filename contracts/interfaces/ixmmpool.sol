// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IXMMPool {
    function changeOwnership(address newOwner) external;

    /// @notice Sets the first fixing and activates the pool
    function setFirstFixing(uint64 spot, uint64 strike, uint64 volatility, int64 optionPremium) external;

    /// @notice Sets the fixing
    function setFixing(uint64 spot, uint64 strike, uint64 volatility, int64 optionPremium) external;
}