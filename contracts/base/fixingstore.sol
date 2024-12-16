// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../structures/fixing.sol";

contract FixingStore {
    // The list of fixings
    uint[] internal _fixingDates;
    mapping(uint => uint) internal _fixingDateToIndex;
    mapping(uint => Fixing) internal _fixings;

    Fixing private _emptyFixing;

    /***************
     * Constructor *
     ***************/
    constructor() { }

    function _addFixing(Fixing memory fixing) internal {
        _fixingDates.push(fixing.timestamp);
        _fixingDateToIndex[fixing.timestamp] = _fixingDates.length - 1;

        Fixing storage f = _fixings[fixing.timestamp];

        f.timestamp = fixing.timestamp;
        f.spot = fixing.spot;
        f.callPremia_t_1__t = fixing.callPremia_t_1__t;
        f.putPremia_t_1__t = fixing.putPremia_t_1__t;
    }

    function _getFixing(uint valueDate) internal view returns(bool, Fixing memory) {
        if (_fixingDates[0] == valueDate) return (true, _fixings[valueDate]);
        if (_fixingDateToIndex[valueDate] == 0) return (false, _emptyFixing);

        return (true, _fixings[valueDate]);
    }

    function _getMissedFixingInfo(uint valueDate) internal view returns(uint64 prevSpot, Fixing storage missedFixing) {
        require(_fixingDateToIndex[valueDate] > 0, 'err missed fix');
        prevSpot = _fixings[_fixingDateToIndex[valueDate] - 1].spot;
        missedFixing = _fixings[valueDate];
    }

    function _getFixings(uint from, uint to) internal view returns (bool, uint[] memory, Fixing[] memory) {
        uint indexStart = _fixingDateToIndex[from];
        uint indexEnd = _fixingDateToIndex[to];

        uint[] memory fixingDates;
        Fixing[] memory fixings;

        if (indexStart == 0 && _fixingDates[0] != from || indexEnd == 0)
        {
            fixingDates = new uint[](0);
            fixings = new Fixing[](0);
            return (false, fixingDates, fixings);
        } else {
            fixingDates = new uint[](to - from + 1);
            fixings = new Fixing[](to - from + 1);
            uint index = 0;

            for (uint i = indexStart; i <= indexEnd; i++) {
                uint fixingDate = _fixingDates[i];
                fixingDates[index] = fixingDate;
                fixings[index] = _fixings[fixingDate];
                index++;
            }

            return (true, fixingDates, fixings);
        }
    }
}