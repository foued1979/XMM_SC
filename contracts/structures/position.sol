// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../enums.sol";

struct Position {
    uint32 positionIndex;
    LongShort position;
    uint fixingIndex;
    uint256 amount;
}