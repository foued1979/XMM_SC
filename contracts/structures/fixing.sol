// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

struct Fixing {
    uint timestamp;
    uint64 forward;
    uint64 strike;
    uint64 volatility;
    uint64 discountRate;
}