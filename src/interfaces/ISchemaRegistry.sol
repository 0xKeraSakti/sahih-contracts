// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISchemaRegistry
/// @author Sahih Contracts
/// @notice Minimal interface for the EAS schema registry contract
interface ISchemaRegistry {
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
}
