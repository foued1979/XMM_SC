// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

library SafeMath {
    function add(uint a, uint b) internal pure returns(uint c) {
        unchecked {
            c = a + b;
            require(c >= a && c >= b, "Overflow");
            return c;
        }
    }

    function add128(uint128 a, uint128 b) internal pure returns(uint128 c) {
        unchecked {
            c = a + b;
            require(c >= a && c >= b, "Overflow");
            return c;
        }
    }

    function sub(uint a, uint b) internal pure returns(uint) {
        unchecked {
            require(a >= b, "Overflow");
            return a - b;
        }
    }

    function sub128(uint128 a, uint128 b) internal pure returns(uint128 c) {
        unchecked {
            require((c = a - b) <= a, "Overflow");
        }
    }

    function subOr0(uint a, uint b) internal pure returns(uint) {
        unchecked {
            return a > b ? 0 : a - b;
        }
    }

    function subOr0_128(uint128 a, uint128 b) internal pure returns(uint128) {
        unchecked {
            return a > b ? 0 : a - b;
        }
    }
}