// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

library SafeMath {
    function SafeAdd128(uint128 a, uint128 b) internal pure returns(uint128 c) {
        require((c = a + b) >= a && c >= b, "Overflow");
    }

    function SafeSub128(uint128 a, uint128 b) internal pure returns(uint128 c) {
        require((c = a - b) <= a, "Overflow");
    }

    function SafeAdd(uint256 a, uint256 b) internal pure returns(uint256 c) {
        require((c = a + b) >= a && c >= b, "Overflow");
    }

    function SafeSub(uint256 a, uint256 b) internal pure returns(uint256 c) {
        require((c = a - b) <= a, "Overflow");
    }
}