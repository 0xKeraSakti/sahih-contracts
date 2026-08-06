// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAttester } from "./interfaces/IAttester.sol";
import { IEAS, AttestationRequest, AttestationRequestData, EASAttestation } from "./interfaces/IEAS.sol";

contract Attester is IAttester, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IEAS public eas;
    bytes32 public verificationSchema;
    bytes32 public scoreSchema;
    bytes32 public distributionSchema;

    uint256[50] private __gap;

    error ZeroAddress();
    error SchemaNotSet();
    error SchemaMismatch(bytes32 expected, bytes32 actual);
    error AttestationNotFound(bytes32 attestationUID);

    constructor() {
        _disableInitializers();
    }

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

    function attestVerification(VerificationPayload calldata payload)
        external
        onlyRole(OPERATOR_ROLE)
        returns (bytes32 attestationUID)
    {
        bytes memory data = abi.encode(
            payload.issuerId,
            payload.period,
            payload.avgRevenue,
            payload.volatilityIndex,
            payload.dataRefHash,
            payload.timestamp
        );
        attestationUID = _attest(verificationSchema, data);

        emit VerificationAttested(payload.issuerId, payload.period, attestationUID);
    }

    function attestScore(ScorePayload calldata payload)
        external
        onlyRole(OPERATOR_ROLE)
        returns (bytes32 attestationUID)
    {
        bytes memory data = abi.encode(
            payload.issuerId, payload.score, payload.scoringMethodVersion, payload.period, payload.timestamp
        );
        attestationUID = _attest(scoreSchema, data);

        emit ScoreAttested(payload.issuerId, payload.period, attestationUID);
    }

    function attestDistribution(DistributionPayload calldata payload)
        external
        onlyRole(OPERATOR_ROLE)
        returns (bytes32 attestationUID)
    {
        bytes memory data = abi.encode(
            payload.issuerId, payload.period, payload.totalAmount, payload.calculationRefHash, payload.timestamp
        );
        attestationUID = _attest(distributionSchema, data);

        emit DistributionAttested(payload.issuerId, payload.period, attestationUID);
    }

    function setSchemas(bytes32 verificationSchema_, bytes32 scoreSchema_, bytes32 distributionSchema_)
        external
        onlyRole(ADMIN_ROLE)
    {
        verificationSchema = verificationSchema_;
        scoreSchema = scoreSchema_;
        distributionSchema = distributionSchema_;

        emit SchemasUpdated(verificationSchema_, scoreSchema_, distributionSchema_);
    }

    function setEAS(address eas_) external onlyRole(ADMIN_ROLE) {
        if (eas_ == address(0)) {
            revert ZeroAddress();
        }
        eas = IEAS(eas_);

        emit EASUpdated(eas_);
    }

    function getAttestation(bytes32 attestationUID) external view returns (EASAttestation memory) {
        return _getAttestation(attestationUID);
    }

    function getVerificationAttestation(bytes32 attestationUID)
        external
        view
        returns (VerificationPayload memory payload, address attesterAddress, uint256 attestedAt)
    {
        EASAttestation memory attestation = _requireSchema(attestationUID, verificationSchema);
        (
            string memory issuerId,
            string memory period,
            uint256 avgRevenue,
            uint256 volatilityIndex,
            bytes32 dataRefHash,
            uint256 timestamp
        ) = abi.decode(attestation.data, (string, string, uint256, uint256, bytes32, uint256));

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

    function getScoreAttestation(bytes32 attestationUID)
        external
        view
        returns (ScorePayload memory payload, address attesterAddress, uint256 attestedAt)
    {
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

    function getDistributionAttestation(bytes32 attestationUID)
        external
        view
        returns (DistributionPayload memory payload, address attesterAddress, uint256 attestedAt)
    {
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

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) { }

    function _attest(bytes32 schema, bytes memory data) private returns (bytes32) {
        if (schema == bytes32(0)) {
            revert SchemaNotSet();
        }

        return eas.attest(
            AttestationRequest({
                schema: schema,
                data: AttestationRequestData({
                    recipient: address(0),
                    expirationTime: 0,
                    revocable: false,
                    refUID: bytes32(0),
                    data: data,
                    value: 0
                })
            })
        );
    }

    function _getAttestation(bytes32 attestationUID) private view returns (EASAttestation memory attestation) {
        attestation = eas.getAttestation(attestationUID);
        if (attestation.uid == bytes32(0)) {
            revert AttestationNotFound(attestationUID);
        }
    }

    function _requireSchema(bytes32 attestationUID, bytes32 expectedSchema)
        private
        view
        returns (EASAttestation memory attestation)
    {
        if (expectedSchema == bytes32(0)) {
            revert SchemaNotSet();
        }

        attestation = _getAttestation(attestationUID);
        if (attestation.schema != expectedSchema) {
            revert SchemaMismatch(expectedSchema, attestation.schema);
        }
    }
}
