// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { EASAttestation } from "./IEAS.sol";

interface IAttester {
    struct VerificationPayload {
        string issuerId;
        string period;
        uint256 avgRevenue;
        uint256 volatilityIndex;
        bytes32 dataRefHash;
        uint256 timestamp;
    }

    struct ScorePayload {
        string issuerId;
        uint256 score;
        string scoringMethodVersion;
        string period;
        uint256 timestamp;
    }

    struct DistributionPayload {
        string issuerId;
        string period;
        uint256 totalAmount;
        bytes32 calculationRefHash;
        uint256 timestamp;
    }

    event VerificationAttested(string indexed issuerId, string period, bytes32 attestationUID);
    event ScoreAttested(string indexed issuerId, string period, bytes32 attestationUID);
    event DistributionAttested(string indexed issuerId, string period, bytes32 attestationUID);
    event SchemasUpdated(bytes32 verificationSchema, bytes32 scoreSchema, bytes32 distributionSchema);
    event EASUpdated(address indexed eas);

    function initialize(
        address eas_,
        bytes32 verificationSchema_,
        bytes32 scoreSchema_,
        bytes32 distributionSchema_,
        address admin,
        address operator
    ) external;

    function attestVerification(VerificationPayload calldata payload) external returns (bytes32);

    function attestScore(ScorePayload calldata payload) external returns (bytes32);

    function attestDistribution(DistributionPayload calldata payload) external returns (bytes32);

    function setSchemas(bytes32 verificationSchema_, bytes32 scoreSchema_, bytes32 distributionSchema_) external;

    function setEAS(address eas_) external;

    function getAttestation(bytes32 attestationUID) external view returns (EASAttestation memory);

    function getVerificationAttestation(bytes32 attestationUID)
        external
        view
        returns (VerificationPayload memory payload, address attesterAddress, uint256 attestedAt);

    function getScoreAttestation(bytes32 attestationUID)
        external
        view
        returns (ScorePayload memory payload, address attesterAddress, uint256 attestedAt);

    function getDistributionAttestation(bytes32 attestationUID)
        external
        view
        returns (DistributionPayload memory payload, address attesterAddress, uint256 attestedAt);
}
