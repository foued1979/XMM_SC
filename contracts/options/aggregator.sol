// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/owned.sol";

contract Aggregator is Owned {

    /// @notice The token managed by the pool
    address public Token;

    /// @notice The mapping of positions
    // Key: the open maturity timestamp
    // Value: the OpenInterests
    mapping(uint => address)

    constructor(address token, address owner) Owned(owner) {
        Token = token;
    }
}