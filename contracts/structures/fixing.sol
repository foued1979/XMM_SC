// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

struct Fixing {
    uint timestamp;
    uint64 spot;
    // The value of Call premium from t - dt to t
    // If spot went up, the Call premium will reflect the increase in value of the spot
    uint64[] callPremia_t_1__t;
    // If spot went down, the Put premium will reflect the decrease in value of the spot
    uint64[] putPremia_t_1__t;
}