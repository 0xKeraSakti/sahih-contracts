// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct AttestationRequestData {
    address recipient;
    uint64 expirationTime;
    bool revocable;
    bytes32 refUID;
    bytes data;
    uint256 value;
}

struct AttestationRequest {
    bytes32 schema;
    AttestationRequestData data;
}

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

interface IEAS {
    function attest(AttestationRequest calldata request) external payable returns (bytes32);

    function getAttestation(bytes32 uid) external view returns (EASAttestation memory);
}
