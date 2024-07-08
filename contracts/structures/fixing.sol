// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

struct Fixing {
    uint timestamp;
    int64 spot;
    int64 strike;
    int64 volatility;
    int64 premium;
}