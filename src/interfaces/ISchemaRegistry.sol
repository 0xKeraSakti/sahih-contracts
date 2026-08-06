// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISchemaRegistry {
    function register(string calldata schema, address resolver, bool revocable) external returns (bytes32);
}
