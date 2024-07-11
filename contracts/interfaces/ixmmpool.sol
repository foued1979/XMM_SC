// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IXMMPool {
    function changeOwnership(address newOwner) external;

    /// @notice Sets the first fixing and activates the pool
    function setFirstFixing(int64 spot, int64 strike, int64 volatility) external;

    /// @notice Sets the fixing
    function setFixing(int64 spot, int64 strike, int64 volatility) external;
}