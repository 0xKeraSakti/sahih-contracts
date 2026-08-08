// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BaseScript } from "./BaseScript.sol";
import { IssuerToken } from "../src/IssuerToken.sol";
import { Factory } from "../src/Factory.sol";
import { Distribution } from "../src/Distribution.sol";
import { Attester } from "../src/Attester.sol";
import { IDistribution } from "../src/interfaces/IDistribution.sol";
import { IAttester } from "../src/interfaces/IAttester.sol";

contract Deploy is BaseScript {
    error MissingEnvAddress(string name);

    function setUp() public virtual {
        // Nothing to do here, but forge-std requires this function to exist.
        vm.createSelectFork(vm.envString("MONAD_TESTNET_RPC_URL"));
    }

    function run()
        external
        returns (address tokenImplementation, address factory, address distributionProxy, address attesterProxy)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address admin = _envAddress("ADMIN_ADDRESS");
        address operator = _envAddress("OPERATOR_ADDRESS");
        address paymentToken = _envAddress("PAYMENT_TOKEN_ADDRESS");
        address eas = _envAddress("EAS_ADDRESS");

        bytes32 verificationSchema = vm.envBytes32("VERIFICATION_SCHEMA_UID");
        bytes32 scoreSchema = vm.envBytes32("SCORE_SCHEMA_UID");
        bytes32 distributionSchema = vm.envBytes32("DISTRIBUTION_SCHEMA_UID");

        vm.startBroadcast(deployerPrivateKey);

        tokenImplementation = address(new IssuerToken());
        factory = address(new Factory(tokenImplementation, admin, operator));

        address distributionImplementation = address(new Distribution());
        distributionProxy = address(
            new ERC1967Proxy(
                distributionImplementation, abi.encodeCall(IDistribution.initialize, (paymentToken, admin, operator))
            )
        );

        address attesterImplementation = address(new Attester());
        attesterProxy = address(
            new ERC1967Proxy(
                attesterImplementation,
                abi.encodeCall(
                    IAttester.initialize, (eas, verificationSchema, scoreSchema, distributionSchema, admin, operator)
                )
            )
        );

        vm.stopBroadcast();

        console2.log("tokenImplementation", tokenImplementation);
        console2.log("factory", factory);
        console2.log("distributionProxy", distributionProxy);
        console2.log("attesterProxy", attesterProxy);
    }

    function _envAddress(
        string memory name
    ) private view returns (address value) {
        value = vm.envAddress(name);
        if (value == address(0)) {
            revert MissingEnvAddress(name);
        }
    }
}
