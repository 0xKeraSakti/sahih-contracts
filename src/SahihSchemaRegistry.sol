// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ISchemaRegistry, SchemaRecord } from "./interfaces/ISchemaRegistry.sol";

/// @title SahihSchemaRegistry
/// @author Sahih Contracts
/// @notice Append-only registry of attestation schema definitions
/// @dev Stands in for the canonical EAS `SchemaRegistry` on chains where EAS is not deployed.
///      UID derivation matches EAS exactly — `keccak256(abi.encodePacked(schema, resolver, revocable))`
///      — so a schema registered here carries the same UID it would on a chain running real EAS,
///      and migrating means repointing an address rather than reissuing identifiers.
contract SahihSchemaRegistry is ISchemaRegistry {
    /// @notice Registered schemas by UID
    mapping(bytes32 => SchemaRecord) private _schemas;

    error EmptySchema();
    error SchemaAlreadyRegistered(bytes32 uid);

    /// @notice Registers a new attestation schema
    /// @param schema Schema definition string
    /// @param resolver Address of the schema resolver contract, or the zero address if none
    /// @param revocable Whether attestations against this schema can be revoked
    /// @return uid UID of the registered schema
    function register(
        string calldata schema,
        address resolver,
        bool revocable
    ) external returns (bytes32 uid) {
        if (bytes(schema).length == 0) {
            revert EmptySchema();
        }

        uid = computeUID(schema, resolver, revocable);
        if (_schemas[uid].uid != bytes32(0)) {
            revert SchemaAlreadyRegistered(uid);
        }

        _schemas[uid] = SchemaRecord({ uid: uid, resolver: resolver, revocable: revocable, schema: schema });

        emit Registered(uid, msg.sender, schema);
    }

    /// @notice Fetches a registered schema by UID
    /// @param uid UID of the schema to fetch
    /// @return The registered schema, or a zero-valued record if the UID is unknown
    function getSchema(
        bytes32 uid
    ) external view returns (SchemaRecord memory) {
        return _schemas[uid];
    }

    /// @notice Checks whether a schema UID has been registered
    /// @param uid UID of the schema to check
    /// @return True if the schema is registered
    function isRegistered(
        bytes32 uid
    ) external view returns (bool) {
        return _schemas[uid].uid != bytes32(0);
    }

    /// @notice Derives the UID a schema will be registered under
    /// @param schema Schema definition string
    /// @param resolver Address of the schema resolver contract, or the zero address if none
    /// @param revocable Whether attestations against this schema can be revoked
    /// @return UID derived for the schema
    function computeUID(
        string memory schema,
        address resolver,
        bool revocable
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(schema, resolver, revocable));
    }
}
