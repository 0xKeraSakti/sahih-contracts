// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title TestConstants
/// @author Sahih Contracts
/// @notice Shared fixture constants used across the test suite
abstract contract TestConstants {
    /// @notice Default issuer ID used in tests
    string internal constant ISSUER_ID = "UMKM-001";
    /// @notice Secondary issuer ID used when a second issuer is needed
    string internal constant ISSUER_ID_SECOND = "UMKM-002";
    /// @notice Default issuer token name
    string internal constant TOKEN_NAME = "Sahih Sukuk UMKM-001";
    /// @notice Default issuer token symbol
    string internal constant TOKEN_SYMBOL = "SHUMKM1";
    /// @notice Default distribution period label
    string internal constant DISTRIBUTION_PERIOD = "weekly";

    /// @notice Sample period identifier: week 31
    string internal constant PERIOD_W31 = "2026-W31";
    /// @notice Sample period identifier: week 32
    string internal constant PERIOD_W32 = "2026-W32";
    /// @notice Sample period identifier: week 33
    string internal constant PERIOD_W33 = "2026-W33";

    /// @notice Default issuer token max supply
    uint256 internal constant MAX_SUPPLY = 10_000;
    /// @notice Default issuer token price per unit
    uint256 internal constant PRICE_PER_UNIT = 100_000;
    /// @notice Default profit sharing ratio, in basis points
    uint256 internal constant PROFIT_SHARING_RATIO = 3000;

    /// @notice Default average revenue used in verification attestations
    uint256 internal constant AVG_REVENUE = 8_500_000;
    /// @notice Default volatility index used in verification attestations
    uint256 internal constant VOLATILITY_INDEX = 12;
    /// @notice Default risk score used in score attestations
    uint256 internal constant RISK_SCORE = 78;
    /// @notice Default scoring method version used in score attestations
    string internal constant SCORING_METHOD_VERSION = "v1.0";

    /// @notice Default off-chain data reference hash
    bytes32 internal constant DATA_REF_HASH = keccak256("data-ref-hash");
    /// @notice Default off-chain calculation reference hash
    bytes32 internal constant CALCULATION_REF_HASH = keccak256("calculation-ref-hash");

    /// @notice Default amount of payment token minted to fund distributions in tests
    uint256 internal constant PAYMENT_TOKEN_FUNDING = 1_000_000_000;
}
