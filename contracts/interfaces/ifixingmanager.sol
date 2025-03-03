// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

interface IFixingManager {
    /// @notice Sets the first fixing and activates the pool
    function setFirstFixing(uint64 spot, uint timestamp, uint64[] memory callPremia, uint64[] memory putPremia) external;

    /// @notice Sets the fixing
    function setFixing(uint64 spot,uint timestamp, uint64[] memory callPremia_t_1__t, uint64[] memory putPremia_t_1__t) external returns(bool);
}