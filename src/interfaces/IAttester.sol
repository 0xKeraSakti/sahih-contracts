// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { EASAttestation } from "./IEAS.sol";

/// @title IAttester
/// @author Sahih Contracts
/// @notice Interface for recording verification, score, and distribution attestations via EAS
interface IAttester {
    /// @notice Payload attested for an issuer's periodic verification data
    struct VerificationPayload {
        string issuerId;
        string period;
        uint256 avgRevenue;
        uint256 volatilityIndex;
        bytes32 dataRefHash;
        uint256 timestamp;
    }

    /// @notice Payload attested for an issuer's periodic score data
    struct ScorePayload {
        string issuerId;
        uint256 score;
        string scoringMethodVersion;
        string period;
        uint256 timestamp;
    }

    /// @notice Payload attested for an issuer's periodic distribution data
    struct DistributionPayload {
        string issuerId;
        string period;
        uint256 totalAmount;
        bytes32 calculationRefHash;
        uint256 timestamp;
    }

    /// @notice Emitted when a verification attestation is recorded
    /// @param issuerId Issuer the attestation is for
    /// @param period Period identifier the attestation covers
    /// @param attestationUID UID of the created attestation
    event VerificationAttested(string indexed issuerId, string indexed period, bytes32 attestationUID);
    /// @notice Emitted when a score attestation is recorded
    /// @param issuerId Issuer the attestation is for
    /// @param period Period identifier the attestation covers
    /// @param attestationUID UID of the created attestation
    event ScoreAttested(string indexed issuerId, string indexed period, bytes32 attestationUID);
    /// @notice Emitted when a distribution attestation is recorded
    /// @param issuerId Issuer the attestation is for
    /// @param period Period identifier the attestation covers
    /// @param attestationUID UID of the created attestation
    event DistributionAttested(string indexed issuerId, string indexed period, bytes32 attestationUID);
    /// @notice Emitted when the verification, score, and distribution schema UIDs are updated
    /// @param verificationSchema New schema UID for verification attestations
    /// @param scoreSchema New schema UID for score attestations
    /// @param distributionSchema New schema UID for distribution attestations
    event SchemasUpdated(
        bytes32 indexed verificationSchema, bytes32 indexed scoreSchema, bytes32 indexed distributionSchema
    );
    /// @notice Emitted when the EAS contract address is updated
    /// @param eas New EAS contract address
    event EASUpdated(address indexed eas);

    /// @notice Initializes the contract, setting the EAS address, schemas, and roles
    /// @param eas_ Address of the Ethereum Attestation Service contract
    /// @param verificationSchema_ Schema UID used for verification attestations
    /// @param scoreSchema_ Schema UID used for score attestations
    /// @param distributionSchema_ Schema UID used for distribution attestations
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    function initialize(
        address eas_,
        bytes32 verificationSchema_,
        bytes32 scoreSchema_,
        bytes32 distributionSchema_,
        address admin,
        address operator
    ) external;

    /// @notice Records a verification attestation for an issuer
    /// @param payload Verification data to encode and attest
    /// @return UID of the created attestation
    function attestVerification(
        VerificationPayload calldata payload
    ) external returns (bytes32);

    /// @notice Records a score attestation for an issuer
    /// @param payload Score data to encode and attest
    /// @return UID of the created attestation
    function attestScore(
        ScorePayload calldata payload
    ) external returns (bytes32);

    /// @notice Records a distribution attestation for an issuer
    /// @param payload Distribution data to encode and attest
    /// @return UID of the created attestation
    function attestDistribution(
        DistributionPayload calldata payload
    ) external returns (bytes32);

    /// @notice Updates the verification, score, and distribution schema UIDs
    /// @param verificationSchema_ New schema UID for verification attestations
    /// @param scoreSchema_ New schema UID for score attestations
    /// @param distributionSchema_ New schema UID for distribution attestations
    function setSchemas(
        bytes32 verificationSchema_,
        bytes32 scoreSchema_,
        bytes32 distributionSchema_
    ) external;

    /// @notice Updates the Ethereum Attestation Service contract address
    /// @param eas_ New EAS contract address
    function setEAS(
        address eas_
    ) external;

    /// @notice Fetches a raw attestation by UID, reverting if it doesn't exist
    /// @param attestationUID UID of the attestation to fetch
    /// @return The raw EAS attestation
    function getAttestation(
        bytes32 attestationUID
    ) external view returns (EASAttestation memory);

    /// @notice Fetches and decodes a verification attestation by UID
    /// @param attestationUID UID of the attestation to fetch
    /// @return payload Decoded verification data
    /// @return attesterAddress Address that submitted the attestation
    /// @return attestedAt Timestamp the attestation was recorded
    function getVerificationAttestation(
        bytes32 attestationUID
    ) external view returns (VerificationPayload memory payload, address attesterAddress, uint256 attestedAt);

    /// @notice Fetches and decodes a score attestation by UID
    /// @param attestationUID UID of the attestation to fetch
    /// @return payload Decoded score data
    /// @return attesterAddress Address that submitted the attestation
    /// @return attestedAt Timestamp the attestation was recorded
    function getScoreAttestation(
        bytes32 attestationUID
    ) external view returns (ScorePayload memory payload, address attesterAddress, uint256 attestedAt);

    /// @notice Fetches and decodes a distribution attestation by UID
    /// @param attestationUID UID of the attestation to fetch
    /// @return payload Decoded distribution data
    /// @return attesterAddress Address that submitted the attestation
    /// @return attestedAt Timestamp the attestation was recorded
    function getDistributionAttestation(
        bytes32 attestationUID
    ) external view returns (DistributionPayload memory payload, address attesterAddress, uint256 attestedAt);
}
