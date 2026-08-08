// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseScript } from "./BaseScript.sol";
import { console2 } from "forge-std/console2.sol";
import { ISchemaRegistry } from "../src/interfaces/ISchemaRegistry.sol";
import { SahihSchemas } from "../src/libraries/SahihSchemas.sol";

/// @title RegisterSchema
/// @author Sahih Contracts
/// @notice Registers the three platform schemas against an existing EAS schema registry
/// @dev Use this on chains running canonical EAS, pointing EAS_SCHEMA_REGISTRY_ADDRESS at the
///      official deployment. On chains without EAS, `DeployAttestationStack.s.sol` deploys a
///      registry and performs this registration in the same run.
contract RegisterSchema is BaseScript {
    error MissingEnvAddress(string name);

    function run() external returns (bytes32 verificationUID, bytes32 scoreUID, bytes32 distributionUID) {
        address registryAddress = vm.envAddress("EAS_SCHEMA_REGISTRY_ADDRESS");
        if (registryAddress == address(0)) {
            revert MissingEnvAddress("EAS_SCHEMA_REGISTRY_ADDRESS");
        }

        ISchemaRegistry registry = ISchemaRegistry(registryAddress);

        _startBroadcast();
        verificationUID = registry.register(SahihSchemas.VERIFICATION, address(0), false);
        scoreUID = registry.register(SahihSchemas.SCORE, address(0), false);
        distributionUID = registry.register(SahihSchemas.DISTRIBUTION, address(0), false);
        vm.stopBroadcast();

        console2.logBytes32(verificationUID);
        console2.logBytes32(scoreUID);
        console2.logBytes32(distributionUID);
    }
}
