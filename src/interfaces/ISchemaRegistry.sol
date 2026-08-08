// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice A registered attestation schema
/// @dev Field order matches the EAS `SchemaRecord` struct so this interface stays a drop-in
///      substitute for the canonical EAS schema registry.
struct SchemaRecord {
    bytes32 uid;
    address resolver;
    bool revocable;
    string schema;
}

/// @title ISchemaRegistry
/// @author Sahih Contracts
/// @notice Minimal interface for an EAS-compatible schema registry
interface ISchemaRegistry {
    /// @notice Emitted when a new schema is registered
    /// @param uid UID derived for the registered schema
    /// @param registerer Address that registered the schema
    /// @param schema Schema definition string that was registered
    event Registered(bytes32 indexed uid, address indexed registerer, string schema);

    /// @notice Registers a new attestation schema
    /// @param schema Schema definition string
    /// @param resolver Address of the schema resolver contract, or the zero address if none
    /// @param revocable Whether attestations against this schema can be revoked
    /// @return UID of the registered schema
    function register(
        string calldata schema,
        address resolver,
        bool revocable
    ) external returns (bytes32);

    /// @notice Fetches a registered schema by UID
    /// @param uid UID of the schema to fetch
    /// @return The registered schema, or a zero-valued record if the UID is unknown
    function getSchema(
        bytes32 uid
    ) external view returns (SchemaRecord memory);
}
