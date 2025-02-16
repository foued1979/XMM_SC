// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

struct OpenInterest {
    address buyer;
    address seller;
    uint40 strike;
    uint256 quantity;
    uint64 premium;
}