// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./fixing.sol";
import "../enums.sol";

struct Position {
    uint32 positionIndex;
    LongShort position;
    Fixing fixing;
    uint expiry;
    uint128 amount;
}