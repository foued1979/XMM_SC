// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

library Utils {
    function itemExistsInArray(address item, address[] into) internal pure return(bool) {
        for (uint i = 0; i < into.length; i++) {
            if (item == into[i]) return true;
        }

        return false;
    }
}