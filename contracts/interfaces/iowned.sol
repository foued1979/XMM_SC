// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IOwned {
    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner) external;
}