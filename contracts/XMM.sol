// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./dependencies/fixed_contributors.sol";
import "./dependencies/float_contributors.sol";

import "./Library.sol";
import "./structures.sol";

contract XMM is FixedContributors, FloatContributors {
    /// @notice The owner of the contract
    address public Owner;

    modifier onlyOwner {
        require(msg.sender == Owner);
        _;
    }

    /// @notice The Term of the XMM
    Terms public Term;

    constructor(Terms term) {
        Owner = msg.sender;
        Term = term;
    }
}