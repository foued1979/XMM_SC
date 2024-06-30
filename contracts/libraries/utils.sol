// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../structures/position.sol";
import "../enums.sol";

library Utils {
    uint internal constant UPDATE_INTERVAL = 14_400;
    uint internal constant MAX_NUMBER_FIXINGS = 4_380;

    /// @notice Checks if an address is in an array of addresses
    function itemExistsInArray(address item, address[] memory intoArray) internal pure returns(bool) {
        for (uint i = 0; i < intoArray.length; i++) {
            if (item == intoArray[i]) return true;
        }

        return false;
    }

    /// @notice Gets the start date of an XMM
    function getStartDate(uint blockTimestamp) internal pure returns(uint) {
        return uint(blockTimestamp / UPDATE_INTERVAL) * UPDATE_INTERVAL;
    }

    /// @notice Reduces the amount of a position
    function reducePosition(Position storage position, uint256 amount) internal returns(LongShort, uint32, uint256, bool) {
        if (amount > position.amount) {
            position.amount = 0;
            return (position.position, position.positionIndex, position.amount, true);
        } else {
            position.amount -= amount;
            return (position.position, position.positionIndex, amount, false);
        }
    }

    function removePositionFromArray(uint32 indexOfItemToRemove, Position[] storage positions) internal {
        if (indexOfItemToRemove == positions.length) {
            positions.pop();
        } else {
            Position storage lastPosition = positions[positions.length - 1];
            lastPosition.positionIndex = indexOfItemToRemove;
            positions[uint(indexOfItemToRemove)] = lastPosition;
        }
    }
}