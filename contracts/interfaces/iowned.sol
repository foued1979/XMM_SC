// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IOwned {
    /// @notice Changes the ownership of the contract
    /// @param activationStatus Enables to get pool activated or deactivated during change of ownership
    function changeOwnership(address newOwner, bool activationStatus) external;
}