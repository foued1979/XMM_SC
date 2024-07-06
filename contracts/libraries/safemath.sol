// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

library SafeMath {
    function SafeAdd(uint128 a, uint128 b) external pure returns(uint128 c) {
        require((c = a + b) > a && c > b, "Overflow");
    }

    function SafeSub(uint128 a, uint128 b) external pure returns(uint128 c) {
        require((c = a - b) < a, "Overflow");
    }
}