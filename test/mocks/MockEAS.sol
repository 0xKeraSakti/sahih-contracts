// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IEAS, AttestationRequest, EASAttestation } from "../../src/interfaces/IEAS.sol";

/// @title MockEAS
/// @author Sahih Contracts
/// @notice Minimal in-memory mock of the Ethereum Attestation Service used in tests
contract MockEAS is IEAS {
    /// @notice Number of attestations recorded so far, used to derive unique UIDs
    uint256 public nonce;
    /// @notice Recorded attestations by UID
    mapping(bytes32 => EASAttestation) private attestations;

    /// @notice Records a mock attestation and returns its derived UID
    /// @param request Attestation request to record
    /// @return uid UID of the recorded attestation
    function attest(
        AttestationRequest calldata request
    ) external payable returns (bytes32) {
        ++nonce;
        bytes32 uid = keccak256(abi.encode(request.schema, request.data.data, msg.sender, nonce));

        attestations[uid] = EASAttestation({
            uid: uid,
            schema: request.schema,
            time: uint64(block.timestamp),
            expirationTime: request.data.expirationTime,
            revocationTime: 0,
            refUID: request.data.refUID,
            recipient: request.data.recipient,
            attester: msg.sender,
            revocable: request.data.revocable,
            data: request.data.data
        });

        return uid;
    }

    /// @notice Fetches a recorded attestation by UID
    /// @param uid UID of the attestation to fetch
    /// @return The recorded attestation
    function getAttestation(
        bytes32 uid
    ) external view returns (EASAttestation memory) {
        return attestations[uid];
    }
}
