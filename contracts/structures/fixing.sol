// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

struct Fixing {
    uint timestamp;
    uint64 spot;
    uint64 strike;
    uint64 volatility;
    uint64 premium;
}