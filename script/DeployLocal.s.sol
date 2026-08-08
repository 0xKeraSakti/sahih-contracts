// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IssuerToken } from "../src/IssuerToken.sol";
import { Factory } from "../src/Factory.sol";
import { Distribution } from "../src/Distribution.sol";
import { Attester } from "../src/Attester.sol";
import { IDistribution } from "../src/interfaces/IDistribution.sol";
import { IAttester } from "../src/interfaces/IAttester.sol";
import { MockEAS } from "../test/mocks/MockEAS.sol";
import { MockToken } from "../test/mocks/MockToken.sol";

/// @title DeployLocal
/// @notice Deploys the full stack plus a mock EAS and mock payment token onto a local anvil node.
/// @dev Base Sepolia has a real EAS deployment; anvil does not, so both dependencies are mocked
///      here. Schema UIDs are derived deterministically from the schema strings used by
///      `RegisterSchema.s.sol` — MockEAS never validates them, it only records them.
contract DeployLocal is Script {
    string public constant VERIFICATION_SCHEMA =
        "string issuerId,string period,uint256 avgRevenue,uint8 volatilityIndex,bytes32 dataRefHash,uint256 timestamp";
    string public constant SCORE_SCHEMA =
        "string issuerId,uint256 score,string scoringMethodVersion,string period,uint256 timestamp";
    string public constant DISTRIBUTION_SCHEMA =
        "string issuerId,string period,uint256 totalAmount,bytes32 calculationRefHash,uint256 timestamp";

    /// @notice Amount of mock payment token minted to admin and operator on deploy
    uint256 public constant FAUCET_AMOUNT = 1_000_000_000 ether;

    function run()
        external
        returns (
            address paymentToken,
            address eas,
            address tokenImplementation,
            address factory,
            address distributionProxy,
            address attesterProxy
        )
    {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");

        bytes32 verificationSchema = keccak256(bytes(VERIFICATION_SCHEMA));
        bytes32 scoreSchema = keccak256(bytes(SCORE_SCHEMA));
        bytes32 distributionSchema = keccak256(bytes(DISTRIBUTION_SCHEMA));

        vm.startBroadcast();

        paymentToken = address(new MockToken("Mock IDRX", "IDRX"));
        eas = address(new MockEAS());

        MockToken(paymentToken).mint(admin, FAUCET_AMOUNT);
        MockToken(paymentToken).mint(operator, FAUCET_AMOUNT);

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

        console2.log("PAYMENT_TOKEN_ADDRESS", paymentToken);
        console2.log("EAS_ADDRESS", eas);
        console2.log("TOKEN_IMPLEMENTATION", tokenImplementation);
        console2.log("FACTORY_ADDRESS", factory);
        console2.log("DISTRIBUTION_PROXY", distributionProxy);
        console2.log("ATTESTER_PROXY", attesterProxy);
        console2.log("VERIFICATION_SCHEMA_UID");
        console2.logBytes32(verificationSchema);
        console2.log("SCORE_SCHEMA_UID");
        console2.logBytes32(scoreSchema);
        console2.log("DISTRIBUTION_SCHEMA_UID");
        console2.logBytes32(distributionSchema);
    }
}
