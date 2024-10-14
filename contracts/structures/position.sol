// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../enums.sol";

struct Position {
    uint32 positionIndex;
    LongShort longShort;
    Leverage leverage;
    uint fixingIndex0;
    uint startDate;
    uint expiry;
    uint128 amount;
    uint128 minFeePaid;
}