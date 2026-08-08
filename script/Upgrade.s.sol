// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseScript } from "./BaseScript.sol";
import { console2 } from "forge-std/console2.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

contract Upgrade is BaseScript {
    error MissingEnvAddress(string name);

    function run() external {
        address proxy = vm.envAddress("UPGRADE_PROXY_ADDRESS");
        if (proxy == address(0)) {
            revert MissingEnvAddress("UPGRADE_PROXY_ADDRESS");
        }

        string memory contractName = vm.envString("UPGRADE_CONTRACT_NAME");
        string memory referenceContract = vm.envOr("UPGRADE_REFERENCE_CONTRACT", string(""));

        Options memory options;
        if (bytes(referenceContract).length != 0) {
            options.referenceContract = referenceContract;
            Upgrades.validateUpgrade(contractName, options);
        }

        _startBroadcast();
        Upgrades.upgradeProxy(proxy, contractName, "", options);
        vm.stopBroadcast();

        console2.log("proxy", proxy);
        console2.log("implementation", Upgrades.getImplementationAddress(proxy));
    }
}
