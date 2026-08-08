// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IEAS, AttestationRequest, EASAttestation } from "./interfaces/IEAS.sol";
import { ISchemaRegistry, SchemaRecord } from "./interfaces/ISchemaRegistry.sol";

/// @title SahihAttestationRegistry
/// @author Sahih Contracts
/// @notice Append-only attestation registry implementing the EAS attestation interface
/// @dev Stands in for the canonical EAS contract on chains where EAS is not deployed (Monad at
///      time of writing). It implements the subset of `IEAS` the platform actually uses, and
///      deliberately does NOT implement revocation, delegated attestation, resolvers, or
///      value-bearing attestations. Attestations here are permanent by construction, which
///      matches the platform's design rule that history is only ever appended to.
///
///      Because `Attester` reaches this contract through `IEAS`, swapping in canonical EAS later
///      is an address change via `Attester.setEAS`, with no contract modification required.
contract SahihAttestationRegistry is IEAS {
    /// @notice Schema registry consulted to validate that a schema exists before attesting
    ISchemaRegistry public immutable SCHEMA_REGISTRY;

    /// @notice Total number of attestations recorded
    uint256 public attestationCount;
    /// @notice Recorded attestations by UID
    mapping(bytes32 => EASAttestation) private _attestations;

    /// @notice Emitted when an attestation is recorded
    /// @param uid UID of the recorded attestation
    /// @param schema Schema UID the attestation was recorded against
    /// @param attester Address that submitted the attestation
    event Attested(bytes32 indexed uid, bytes32 indexed schema, address indexed attester);

    error ZeroAddress();
    error SchemaNotRegistered(bytes32 schema);
    error RevocationNotSupported();
    error ValueNotAccepted();

    /// @notice Deploys the registry against a schema registry
    /// @param schemaRegistry Registry consulted to validate schemas before attesting
    constructor(
        ISchemaRegistry schemaRegistry
    ) {
        if (address(schemaRegistry) == address(0)) {
            revert ZeroAddress();
        }
        SCHEMA_REGISTRY = schemaRegistry;
    }

    /// @notice Records an attestation against a registered schema
    /// @param request Schema UID and attestation request data
    /// @return uid UID of the recorded attestation
    function attest(
        AttestationRequest calldata request
    ) external payable returns (bytes32 uid) {
        if (msg.value != 0 || request.data.value != 0) {
            revert ValueNotAccepted();
        }
        if (request.data.revocable) {
            revert RevocationNotSupported();
        }

        SchemaRecord memory schemaRecord = SCHEMA_REGISTRY.getSchema(request.schema);
        if (schemaRecord.uid == bytes32(0)) {
            revert SchemaNotRegistered(request.schema);
        }

        uid = _deriveUID(request, msg.sender);

        _attestations[uid] = EASAttestation({
            uid: uid,
            schema: request.schema,
            time: uint64(block.timestamp),
            expirationTime: request.data.expirationTime,
            revocationTime: 0,
            refUID: request.data.refUID,
            recipient: request.data.recipient,
            attester: msg.sender,
            revocable: false,
            data: request.data.data
        });
        ++attestationCount;

        emit Attested(uid, request.schema, msg.sender);
    }

    /// @notice Fetches a recorded attestation by UID
    /// @param uid UID of the attestation to fetch
    /// @return The recorded attestation, or a zero-valued attestation if the UID is unknown
    /// @dev Matches EAS behaviour by returning an empty struct rather than reverting; callers
    ///      detect absence via a zero `uid` field.
    function getAttestation(
        bytes32 uid
    ) external view returns (EASAttestation memory) {
        return _attestations[uid];
    }

    /// @notice Derives a collision-free UID for an attestation request
    /// @param request Schema UID and attestation request data
    /// @param attester Address submitting the attestation
    /// @return uid A UID not already in use
    /// @dev Mirrors the EAS derivation, including the bump used to disambiguate two identical
    ///      attestations submitted in the same block by the same attester.
    function _deriveUID(
        AttestationRequest calldata request,
        address attester
    ) private view returns (bytes32 uid) {
        uint32 bump = 0;
        while (true) {
            uid = keccak256(
                abi.encodePacked(
                    request.schema,
                    request.data.recipient,
                    attester,
                    uint64(block.timestamp),
                    request.data.expirationTime,
                    request.data.refUID,
                    request.data.data,
                    bump
                )
            );
            if (_attestations[uid].uid == bytes32(0)) {
                return uid;
            }
            unchecked {
                ++bump;
            }
        }
    }
}
