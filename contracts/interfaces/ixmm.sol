// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./structures.sol";

interface IXMM {
    /// @notice Gets the term of the XMM
    function getTerm() external view returns(Terms);

    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner) external;
}