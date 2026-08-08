// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAttester } from "./interfaces/IAttester.sol";
import { IEAS, AttestationRequest, AttestationRequestData, EASAttestation } from "./interfaces/IEAS.sol";

/// @title Attester
/// @author Sahih Contracts
/// @notice Records verification, score, and distribution attestations via EAS
contract Attester is IAttester, AccessControlUpgradeable, UUPSUpgradeable {
    /// @notice Role allowed to update schemas and the EAS address
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role allowed to submit attestations
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice The Ethereum Attestation Service contract used to record attestations
    IEAS public eas;
    /// @notice Schema UID used for verification attestations
    bytes32 public verificationSchema;
    /// @notice Schema UID used for score attestations
    bytes32 public scoreSchema;
    /// @notice Schema UID used for distribution attestations
    bytes32 public distributionSchema;
    /// @notice Latest attestation UID for a given kind, issuer, and period
    mapping(bytes32 => bytes32) private _attestationIndex;

    uint256[49] private __gap;

    error ZeroAddress();
    error SchemaNotSet();
    error SchemaMismatch(bytes32 expected, bytes32 actual);
    error AttestationNotFound(bytes32 attestationUID);

    /// @notice Disables initializers on the implementation contract
    constructor() {
        _disableInitializers();
    }

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
    ) external initializer {
        if (eas_ == address(0) || admin == address(0) || operator == address(0)) {
            revert ZeroAddress();
        }

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);

        eas = IEAS(eas_);
        verificationSchema = verificationSchema_;
        scoreSchema = scoreSchema_;
        distributionSchema = distributionSchema_;

        emit EASUpdated(eas_);
        emit SchemasUpdated(verificationSchema_, scoreSchema_, distributionSchema_);
    }

    /// @notice Records a verification attestation for an issuer
    /// @param payload Verification data to encode and attest
    /// @return attestationUID UID of the created attestation
    function attestVerification(
        VerificationPayload calldata payload
    ) external onlyRole(OPERATOR_ROLE) returns (bytes32 attestationUID) {
        bytes memory data = abi.encode(
            payload.issuerId,
            payload.period,
            payload.avgRevenue,
            payload.volatilityIndex,
            payload.dataRefHash,
            payload.timestamp
        );
        attestationUID = _attest(verificationSchema, data);
        _index(AttestationKind.Verification, payload.issuerId, payload.period, attestationUID);

        emit VerificationAttested(keccak256(bytes(payload.issuerId)), attestationUID, payload.issuerId, payload.period);
    }

    /// @notice Records a score attestation for an issuer
    /// @param payload Score data to encode and attest
    /// @return attestationUID UID of the created attestation
    function attestScore(
        ScorePayload calldata payload
    ) external onlyRole(OPERATOR_ROLE) returns (bytes32 attestationUID) {
        bytes memory data = abi.encode(
            payload.issuerId, payload.score, payload.scoringMethodVersion, payload.period, payload.timestamp
        );
        attestationUID = _attest(scoreSchema, data);
        _index(AttestationKind.Score, payload.issuerId, payload.period, attestationUID);

        emit ScoreAttested(keccak256(bytes(payload.issuerId)), attestationUID, payload.issuerId, payload.period);
    }

    /// @notice Records a distribution attestation for an issuer
    /// @param payload Distribution data to encode and attest
    /// @return attestationUID UID of the created attestation
    function attestDistribution(
        DistributionPayload calldata payload
    ) external onlyRole(OPERATOR_ROLE) returns (bytes32 attestationUID) {
        bytes memory data = abi.encode(
            payload.issuerId, payload.period, payload.totalAmount, payload.calculationRefHash, payload.timestamp
        );
        attestationUID = _attest(distributionSchema, data);
        _index(AttestationKind.Distribution, payload.issuerId, payload.period, attestationUID);

        emit DistributionAttested(keccak256(bytes(payload.issuerId)), attestationUID, payload.issuerId, payload.period);
    }

    /// @notice Updates the verification, score, and distribution schema UIDs
    /// @param verificationSchema_ New schema UID for verification attestations
    /// @param scoreSchema_ New schema UID for score attestations
    /// @param distributionSchema_ New schema UID for distribution attestations
    function setSchemas(
        bytes32 verificationSchema_,
        bytes32 scoreSchema_,
        bytes32 distributionSchema_
    ) external onlyRole(ADMIN_ROLE) {
        verificationSchema = verificationSchema_;
        scoreSchema = scoreSchema_;
        distributionSchema = distributionSchema_;

        emit SchemasUpdated(verificationSchema_, scoreSchema_, distributionSchema_);
    }

    /// @notice Updates the Ethereum Attestation Service contract address
    /// @param eas_ New EAS contract address
    function setEAS(
        address eas_
    ) external onlyRole(ADMIN_ROLE) {
        if (eas_ == address(0)) {
            revert ZeroAddress();
        }
        eas = IEAS(eas_);

        emit EASUpdated(eas_);
    }

    /// @notice Looks up the most recent attestation UID for an issuer, period, and kind
    /// @dev Lets an issuer's attestation history be recovered straight from the chain rather than
    /// relying on an off-chain index of UIDs
    /// @param kind Which of the three attestation kinds to look up
    /// @param issuerId Issuer the attestation belongs to
    /// @param period Period identifier the attestation covers
    /// @return UID of the latest matching attestation, or zero if none exists
    function getAttestationUID(
        AttestationKind kind,
        string calldata issuerId,
        string calldata period
    ) external view returns (bytes32) {
        return _attestationIndex[_indexKey(kind, issuerId, period)];
    }

    /// @notice Fetches a raw attestation by UID, reverting if it doesn't exist
    /// @param attestationUID UID of the attestation to fetch
    /// @return The raw EAS attestation
    function getAttestation(
        bytes32 attestationUID
    ) external view returns (EASAttestation memory) {
        return _getAttestation(attestationUID);
    }

    /// @notice Fetches and decodes a verification attestation by UID
    /// @param attestationUID UID of the attestation to fetch
    /// @return payload Decoded verification data
    /// @return attesterAddress Address that submitted the attestation
    /// @return attestedAt Timestamp the attestation was recorded
    function getVerificationAttestation(
        bytes32 attestationUID
    ) external view returns (VerificationPayload memory payload, address attesterAddress, uint256 attestedAt) {
        EASAttestation memory attestation = _requireSchema(attestationUID, verificationSchema);
        (
            string memory issuerId,
            string memory period,
            uint256 avgRevenue,
            uint8 volatilityIndex,
            bytes32 dataRefHash,
            uint256 timestamp
        ) = abi.decode(attestation.data, (string, string, uint256, uint8, bytes32, uint256));

        payload = VerificationPayload({
            issuerId: issuerId,
            period: period,
            avgRevenue: avgRevenue,
            volatilityIndex: volatilityIndex,
            dataRefHash: dataRefHash,
            timestamp: timestamp
        });
        attesterAddress = attestation.attester;
        attestedAt = uint256(attestation.time);
    }

    /// @notice Fetches and decodes a score attestation by UID
    /// @param attestationUID UID of the attestation to fetch
    /// @return payload Decoded score data
    /// @return attesterAddress Address that submitted the attestation
    /// @return attestedAt Timestamp the attestation was recorded
    function getScoreAttestation(
        bytes32 attestationUID
    ) external view returns (ScorePayload memory payload, address attesterAddress, uint256 attestedAt) {
        EASAttestation memory attestation = _requireSchema(attestationUID, scoreSchema);
        (
            string memory issuerId,
            uint256 score,
            string memory scoringMethodVersion,
            string memory period,
            uint256 timestamp
        ) = abi.decode(attestation.data, (string, uint256, string, string, uint256));

        payload = ScorePayload({
            issuerId: issuerId,
            score: score,
            scoringMethodVersion: scoringMethodVersion,
            period: period,
            timestamp: timestamp
        });
        attesterAddress = attestation.attester;
        attestedAt = uint256(attestation.time);
    }

    /// @notice Fetches and decodes a distribution attestation by UID
    /// @param attestationUID UID of the attestation to fetch
    /// @return payload Decoded distribution data
    /// @return attesterAddress Address that submitted the attestation
    /// @return attestedAt Timestamp the attestation was recorded
    function getDistributionAttestation(
        bytes32 attestationUID
    ) external view returns (DistributionPayload memory payload, address attesterAddress, uint256 attestedAt) {
        EASAttestation memory attestation = _requireSchema(attestationUID, distributionSchema);
        (
            string memory issuerId,
            string memory period,
            uint256 totalAmount,
            bytes32 calculationRefHash,
            uint256 timestamp
        ) = abi.decode(attestation.data, (string, string, uint256, bytes32, uint256));

        payload = DistributionPayload({
            issuerId: issuerId,
            period: period,
            totalAmount: totalAmount,
            calculationRefHash: calculationRefHash,
            timestamp: timestamp
        });
        attesterAddress = attestation.attester;
        attestedAt = uint256(attestation.time);
    }

    // solhint-disable no-empty-blocks
    /// @notice Authorizes a UUPS upgrade; restricted to the admin role
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

    // solhint-enable no-empty-blocks

    /// @notice Records an attestation UID under its issuer, period, and kind
    /// @param kind Which of the three attestation kinds this is
    /// @param issuerId Issuer the attestation belongs to
    /// @param period Period identifier the attestation covers
    /// @param attestationUID UID to record
    function _index(
        AttestationKind kind,
        string calldata issuerId,
        string calldata period,
        bytes32 attestationUID
    ) private {
        _attestationIndex[_indexKey(kind, issuerId, period)] = attestationUID;
    }

    /// @notice Builds the index key for an attestation kind, issuer, and period
    /// @param kind Which of the three attestation kinds this is
    /// @param issuerId Issuer the attestation belongs to
    /// @param period Period identifier the attestation covers
    /// @return The index key
    function _indexKey(
        AttestationKind kind,
        string calldata issuerId,
        string calldata period
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(kind, issuerId, period));
    }

    /// @notice Submits an attestation to EAS for the given schema and encoded data
    /// @param schema Schema UID to attest against
    /// @param data ABI-encoded attestation payload
    /// @return UID of the created attestation
    function _attest(
        bytes32 schema,
        bytes memory data
    ) private returns (bytes32) {
        if (schema == bytes32(0)) {
            revert SchemaNotSet();
        }

        return eas.attest(
            AttestationRequest({
                schema: schema,
                data: AttestationRequestData({
                    recipient: address(0), expirationTime: 0, revocable: false, refUID: bytes32(0), data: data, value: 0
                })
            })
        );
    }

    /// @notice Fetches an attestation from EAS by UID, reverting if it doesn't exist
    /// @param attestationUID UID of the attestation to fetch
    /// @return attestation The raw EAS attestation
    function _getAttestation(
        bytes32 attestationUID
    ) private view returns (EASAttestation memory attestation) {
        attestation = eas.getAttestation(attestationUID);
        if (attestation.uid == bytes32(0)) {
            revert AttestationNotFound(attestationUID);
        }
    }

    /// @notice Fetches an attestation and verifies it matches the expected schema
    /// @param attestationUID UID of the attestation to fetch
    /// @param expectedSchema Schema UID the attestation must match
    /// @return attestation The raw EAS attestation
    function _requireSchema(
        bytes32 attestationUID,
        bytes32 expectedSchema
    ) private view returns (EASAttestation memory attestation) {
        if (expectedSchema == bytes32(0)) {
            revert SchemaNotSet();
        }

        attestation = _getAttestation(attestationUID);
        if (attestation.schema != expectedSchema) {
            revert SchemaMismatch(expectedSchema, attestation.schema);
        }
    }
}
