// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "./BaseScript.sol";
import { SahihSchemaRegistry } from "../src/SahihSchemaRegistry.sol";
import { SahihAttestationRegistry } from "../src/SahihAttestationRegistry.sol";
import { SahihSchemas } from "../src/libraries/SahihSchemas.sol";

/// @title DeployAttestationStack
/// @author Sahih Contracts
/// @notice Deploys a self-hosted attestation stack for chains where EAS is not available
/// @dev Run this BEFORE `Deploy.s.sol`, then copy the logged addresses and schema UIDs into the
///      environment as EAS_SCHEMA_REGISTRY_ADDRESS, EAS_ADDRESS, and the three *_SCHEMA_UID vars.
///
///      On a chain that already runs canonical EAS (Base, Optimism, Arbitrum, …) do NOT run this.
///      Use the official EAS deployment addresses and register schemas with `RegisterSchema.s.sol`
///      instead — nothing else in the system changes, because `Attester` depends only on `IEAS`.
contract DeployAttestationStack is BaseScript {
    function setUp() public virtual {
        // Nothing to do here, but forge-std requires this function to exist.
        vm.createSelectFork(vm.envString("MONAD_TESTNET_RPC_URL"));
    }

    function run()
        external
        returns (
            address schemaRegistry,
            address attestationRegistry,
            bytes32 verificationUID,
            bytes32 scoreUID,
            bytes32 distributionUID
        )
    {
        _startBroadcast();

        SahihSchemaRegistry registry = new SahihSchemaRegistry();
        verificationUID = registry.register(SahihSchemas.VERIFICATION, address(0), false);
        scoreUID = registry.register(SahihSchemas.SCORE, address(0), false);
        distributionUID = registry.register(SahihSchemas.DISTRIBUTION, address(0), false);

        SahihAttestationRegistry attestations = new SahihAttestationRegistry(registry);

        vm.stopBroadcast();

        schemaRegistry = address(registry);
        attestationRegistry = address(attestations);

        console2.log("EAS_SCHEMA_REGISTRY_ADDRESS", schemaRegistry);
        console2.log("EAS_ADDRESS", attestationRegistry);
        console2.log("VERIFICATION_SCHEMA_UID");
        console2.logBytes32(verificationUID);
        console2.log("SCORE_SCHEMA_UID");
        console2.logBytes32(scoreUID);
        console2.log("DISTRIBUTION_SCHEMA_UID");
        console2.logBytes32(distributionUID);
    }
}
