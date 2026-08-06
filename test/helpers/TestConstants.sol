// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract TestConstants {
    string internal constant ISSUER_ID = "UMKM-001";
    string internal constant ISSUER_ID_SECOND = "UMKM-002";
    string internal constant TOKEN_NAME = "Sahih Sukuk UMKM-001";
    string internal constant TOKEN_SYMBOL = "SHUMKM1";
    string internal constant DISTRIBUTION_PERIOD = "weekly";

    string internal constant PERIOD_W31 = "2026-W31";
    string internal constant PERIOD_W32 = "2026-W32";
    string internal constant PERIOD_W33 = "2026-W33";

    uint256 internal constant MAX_SUPPLY = 10_000;
    uint256 internal constant PRICE_PER_UNIT = 100_000;
    uint256 internal constant PROFIT_SHARING_RATIO = 3_000;

    uint256 internal constant AVG_REVENUE = 8_500_000;
    uint256 internal constant VOLATILITY_INDEX = 12;
    uint256 internal constant RISK_SCORE = 78;
    string internal constant SCORING_METHOD_VERSION = "v1.0";

    bytes32 internal constant DATA_REF_HASH = keccak256("data-ref-hash");
    bytes32 internal constant CALCULATION_REF_HASH = keccak256("calculation-ref-hash");

    uint256 internal constant PAYMENT_TOKEN_FUNDING = 1_000_000_000;
}
