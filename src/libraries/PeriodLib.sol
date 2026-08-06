// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PeriodLib
/// @author Sahih Contracts
/// @notice Lexicographic comparison helpers for period identifier strings
library PeriodLib {
    /// @notice Lexicographically compares two period strings
    /// @param left First period string to compare
    /// @param right Second period string to compare
    /// @return Negative if `left` < `right`, positive if `left` > `right`, zero if equal
    function compare(
        string memory left,
        string memory right
    ) internal pure returns (int256) {
        bytes memory a = bytes(left);
        bytes memory b = bytes(right);
        uint256 shortest = a.length < b.length ? a.length : b.length;

        for (uint256 i = 0; i < shortest; ++i) {
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

    /// @notice Checks whether two period strings are equal
    /// @param left First period string to compare
    /// @param right Second period string to compare
    /// @return True if the strings are equal
    function equals(
        string memory left,
        string memory right
    ) internal pure returns (bool) {
        return keccak256(bytes(left)) == keccak256(bytes(right));
    }

    /// @notice Checks whether a period falls within an inclusive range
    /// @param value Period string to check
    /// @param fromPeriod Start of the inclusive range
    /// @param toPeriod End of the inclusive range
    /// @return True if `value` is within `[fromPeriod, toPeriod]`
    function isWithin(
        string memory value,
        string memory fromPeriod,
        string memory toPeriod
    ) internal pure returns (bool) {
        return !(compare(value, fromPeriod) < 0) && !(compare(value, toPeriod) > 0);
    }

    /// @notice Checks whether a period string is empty
    /// @param value Period string to check
    /// @return True if the string has zero length
    function isEmpty(
        string memory value
    ) internal pure returns (bool) {
        return bytes(value).length == 0;
    }
}
