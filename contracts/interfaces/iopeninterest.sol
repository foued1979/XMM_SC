// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../enums.sol";
import "../structures/openinterest.sol";

interface IOpenInterest {
    /// @notice Adds a new open interest
    function addOpenInterest(address buyer, address seller, uint256 quantity, uint40 strike, uint64 premium, OptionTypes optionType) external;

    /// @notice Gets the total open interests by strikes, for calls and puts
    function getTotalOpenInterests() external returns(uint40[] memory callStrikes, uint256[] memory callQuantities, uint40[] memory putStrikes, uint256[] memory putQuantities);

    /// @notice Gets the open interest for a user
    function getOpenInterestsForUser(address user) external returns(OpenInterest[] memory calls, OpenInterest[] memory puts);
}