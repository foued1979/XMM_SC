// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

library SafeMath {
    function SafeAdd128(uint128 a, uint128 b) internal pure returns(uint128 c) {
        unchecked {
            c = a + b;
            require(c >= a && c >= b, "Overflow");
            return c;
        }
    }

    function SafeSub128(uint128 a, uint128 b) internal pure returns(uint128 c) {
        unchecked {
            require(a >= b, "Overflow");
            return a - b;
        }
    }

    function SafeAdd(uint256 a, uint256 b) internal pure returns(uint256 c) {
        require((c = a + b) >= a && c >= b, "Overflow");
    }

    function SafeSub(uint256 a, uint256 b) internal pure returns(uint256 c) {
        unchecked {
            require(a >= b, "Overflow");
            return a - b;
        }
    }

    function SubOr0(uint256 a, uint256 b) internal pure returns(uint256 c) {
        unchecked {
            return a > b ? 0 : a - b;
        }
    }
}