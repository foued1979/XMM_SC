// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

interface IKYC {
    /// @notice Sets the KYC status for a user
    /// @param user The user address
    function updateKYCUserStatus(address user, bool status) external;
}