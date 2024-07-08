// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./fixing.sol";
import "../enums.sol";

struct Position {
    uint32 positionIndex;
    LongShort position;
    int64 index0;
    uint startDate;
    uint expiry;
    uint128 amount;
}