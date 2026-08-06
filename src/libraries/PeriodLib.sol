// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library PeriodLib {
    function compare(string memory left, string memory right) internal pure returns (int256) {
        bytes memory a = bytes(left);
        bytes memory b = bytes(right);
        uint256 shortest = a.length < b.length ? a.length : b.length;

        for (uint256 i = 0; i < shortest; i++) {
            if (uint8(a[i]) < uint8(b[i])) {
                return -1;
            }
            if (uint8(a[i]) > uint8(b[i])) {
                return 1;
            }
        }

        if (a.length < b.length) {
            return -1;
        }
        if (a.length > b.length) {
            return 1;
        }
        return 0;
    }

    function equals(string memory left, string memory right) internal pure returns (bool) {
        return keccak256(bytes(left)) == keccak256(bytes(right));
    }

    function isWithin(string memory value, string memory fromPeriod, string memory toPeriod)
        internal
        pure
        returns (bool)
    {
        return compare(value, fromPeriod) >= 0 && compare(value, toPeriod) <= 0;
    }

    function isEmpty(string memory value) internal pure returns (bool) {
        return bytes(value).length == 0;
    }
}
