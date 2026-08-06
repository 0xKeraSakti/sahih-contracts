// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Data describing the recipient and terms of an attestation request
struct AttestationRequestData {
    address recipient;
    uint64 expirationTime;
    bool revocable;
    bytes32 refUID;
    bytes data;
    uint256 value;
}

/// @notice A request to create an attestation against a given schema
struct AttestationRequest {
    bytes32 schema;
    AttestationRequestData data;
}

/// @notice A recorded EAS attestation
struct EASAttestation {
    bytes32 uid;
    bytes32 schema;
    uint64 time;
    uint64 expirationTime;
    uint64 revocationTime;
    bytes32 refUID;
    address recipient;
    address attester;
    bool revocable;
    bytes data;
}

/// @title IEAS
/// @author Sahih Contracts
/// @notice Minimal interface for the Ethereum Attestation Service contract
interface IEAS {
    /// @notice Creates an attestation for the given schema and request data
    /// @param request Schema UID and attestation request data
    /// @return UID of the created attestation
    function attest(
        AttestationRequest calldata request
    ) external payable returns (bytes32);

    /// @notice Fetches a recorded attestation by UID
    /// @param uid UID of the attestation to fetch
    /// @return The recorded attestation
    function getAttestation(
        bytes32 uid
    ) external view returns (EASAttestation memory);
}
