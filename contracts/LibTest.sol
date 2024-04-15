// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./Library.sol";

contract LibTest {
    address public Owner;

    constructor()
    {
        Owner = msg.sender;
    }

    function add(int64 a, int64 b) public pure returns(int64) {
        return Math.add(a, b);
    }

    function div(int64 a, int64 b) public pure returns(int64) {
        return Math.div(a, b);
    }

    function inverse(int64 a) public pure returns(int64) {
        return Math.inverse(a);
    }

    function mult(int64 a, int64 b) public pure returns(int64) {
        return Math.mult(a, b);
    }

    function sqrt(int64 a) public pure returns(int64) {
        return Math.sqrt(a);
    }

    function pow(int64 a, uint8 b) public pure returns(int64, uint8) {
        return Math.pow(a, b);
    }

    function ln(int64 a) public pure returns(int64) {
        return Math.ln(a);
    }

    function exp(int64 a) public pure returns(int64) {
        return Math.exp(a);
    }
}