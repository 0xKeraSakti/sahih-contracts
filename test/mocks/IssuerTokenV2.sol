// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IssuerToken } from "../../src/IssuerToken.sol";

/// @title IssuerTokenV2
/// @author Sahih Contracts
/// @notice Mock upgraded IssuerToken implementation used to test UUPS upgrades
contract IssuerTokenV2 is IssuerToken {
    /// @notice Version marker used to verify the upgrade took effect
    string public constant VERSION = "v2";

    /// @notice Mock secondary market fee, in basis points
    uint256 public secondaryMarketFeeBps;

    /// @notice Emitted when the secondary market fee is updated
    /// @param feeBps New fee, in basis points
    event SecondaryMarketFeeUpdated(uint256 indexed feeBps);

    /// @notice Thrown when the requested fee exceeds 100%
    error FeeTooHigh(uint256 feeBps);

    /// @notice Updates the mock secondary market fee
    /// @param feeBps New fee, in basis points
    function setSecondaryMarketFee(
        uint256 feeBps
    ) external onlyRole(ADMIN_ROLE) {
        if (feeBps > 10_000) {
            revert FeeTooHigh(feeBps);
        }
        secondaryMarketFeeBps = feeBps;

        emit SecondaryMarketFeeUpdated(feeBps);
    }
}
