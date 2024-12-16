// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../enums.sol";

struct Position {
    uint32 positionIndex;
    LongShort longShort;
    Terms term;
    uint startDate;
    uint min_expiry;
    uint128 amount;
    uint128 minFeePaid;
}