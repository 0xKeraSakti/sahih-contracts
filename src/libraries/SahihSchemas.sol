// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SahihSchemas
/// @author Sahih Contracts
/// @notice Canonical attestation schema definitions used by the platform
/// @dev These strings are the single source of truth for schema layout. Both the registration
///      script and the test fixtures derive their schema UIDs from these constants, so a change
///      here propagates to every consumer instead of drifting between script and contract.
library SahihSchemas {
    /// @notice Schema definition for an issuer's periodic revenue verification
    string internal constant VERIFICATION =
        "string issuerId,string period,uint256 avgRevenue,uint256 volatilityIndex,bytes32 dataRefHash,uint256 timestamp";
    /// @notice Schema definition for an issuer's periodic risk score
    string internal constant SCORE =
        "string issuerId,uint256 score,string scoringMethodVersion,string period,uint256 timestamp";
    /// @notice Schema definition for an issuer's periodic profit distribution
    string internal constant DISTRIBUTION =
        "string issuerId,string period,uint256 totalAmount,bytes32 calculationRefHash,uint256 timestamp";
}
