// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "./BaseScript.sol";
import { DemoPaymentToken } from "../src/DemoPaymentToken.sol";

/// @title DeployDemoPaymentToken
/// @author Sahih Contracts
/// @notice Deploys the free-mint demo payment token and seeds the deployer with a balance
/// @dev Run this BEFORE `Deploy.s.sol`, which needs PAYMENT_TOKEN_ADDRESS set.
///      DEMO AND TESTNET ONLY — the deployed token lets anyone mint without limit.
///      On a network handling real money, skip this and point PAYMENT_TOKEN_ADDRESS at a
///      real IDR stablecoin instead.
contract DeployDemoPaymentToken is BaseScript {
    /// @notice Amount minted to the deployer so distributions can be funded immediately
    uint256 public constant INITIAL_MINT = 1_000_000_000;

    function setUp() public virtual {
        // Nothing to do here, but forge-std requires this function to exist.
        vm.createSelectFork(vm.envString("MONAD_TESTNET_RPC_URL"));
    }

    function run() external returns (address paymentToken) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory name = vm.envOr("DEMO_TOKEN_NAME", string("Sahih Demo Rupiah"));
        string memory symbol = vm.envOr("DEMO_TOKEN_SYMBOL", string("dIDR"));

        vm.startBroadcast(deployerPrivateKey);

        DemoPaymentToken token = new DemoPaymentToken(name, symbol);
        token.mint(msg.sender, INITIAL_MINT);

        vm.stopBroadcast();

        paymentToken = address(token);

        console2.log("PAYMENT_TOKEN_ADDRESS", paymentToken);
        console2.log("name", name);
        console2.log("symbol", symbol);
        console2.log("decimals (1 unit = Rp1)", token.decimals());
        console2.log("minted to deployer", INITIAL_MINT);
    }
}
