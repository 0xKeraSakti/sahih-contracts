// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";

/// @title BaseScript
/// @author Sahih Contracts
/// @notice Shared broadcast setup for the deployment scripts
/// @dev Do NOT add a `setUp()` that calls `vm.createSelectFork` to any script here. The network
///      comes from `--rpc-url`; forking inside a broadcasting script swaps out the EVM the script
///      contract itself lives in, which makes forge record transactions against addresses that
///      hold no code on the target chain.
abstract contract BaseScript is Script {
    /// @notice Starts a broadcast, taking the signer from the environment when one is configured
    /// @dev Prefers DEPLOYER_PRIVATE_KEY, then PRIVATE_KEY, and otherwise falls back to the signer
    ///      supplied on the command line via `--private-key`, `--account`, or `--ledger`. An unset
    ///      or empty variable reads as zero, so a partially filled .env falls through cleanly
    ///      rather than reverting.
    function _startBroadcast() internal {
        uint256 deployerKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        if (deployerKey == 0) {
            deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        }

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
    }

    /// @notice Starts a broadcast with an explicitly supplied signing key
    /// @param deployerKey Private key to broadcast with; zero falls back to the environment or CLI signer
    /// @dev Overload for scripts that read the key themselves. Passing zero is safe — it defers to
    ///      the same resolution order as the no-argument form rather than reverting.
    function _startBroadcast(
        uint256 deployerKey
    ) internal {
        if (deployerKey == 0) {
            _startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
    }
}
