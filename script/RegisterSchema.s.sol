// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ISchemaRegistry } from "../src/interfaces/ISchemaRegistry.sol";

contract RegisterSchema is Script {
    string public constant VERIFICATION_SCHEMA =
        "string issuerId,string period,uint256 avgRevenue,uint256 volatilityIndex,bytes32 dataRefHash,uint256 timestamp";
    string public constant SCORE_SCHEMA =
        "string issuerId,uint256 score,string scoringMethodVersion,string period,uint256 timestamp";
    string public constant DISTRIBUTION_SCHEMA =
        "string issuerId,string period,uint256 totalAmount,bytes32 calculationRefHash,uint256 timestamp";

    error MissingEnvAddress(string name);

    function run() external returns (bytes32 verificationUID, bytes32 scoreUID, bytes32 distributionUID) {
        address registryAddress = vm.envAddress("EAS_SCHEMA_REGISTRY_ADDRESS");
        if (registryAddress == address(0)) {
            revert MissingEnvAddress("EAS_SCHEMA_REGISTRY_ADDRESS");
        }

        ISchemaRegistry registry = ISchemaRegistry(registryAddress);

        vm.startBroadcast();
        verificationUID = registry.register(VERIFICATION_SCHEMA, address(0), false);
        scoreUID = registry.register(SCORE_SCHEMA, address(0), false);
        distributionUID = registry.register(DISTRIBUTION_SCHEMA, address(0), false);
        vm.stopBroadcast();

        console2.logBytes32(verificationUID);
        console2.logBytes32(scoreUID);
        console2.logBytes32(distributionUID);
    }
}
