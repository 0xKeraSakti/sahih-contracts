// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { Factory } from "../../src/Factory.sol";
import { Distribution } from "../../src/Distribution.sol";
import { Attester } from "../../src/Attester.sol";
import { IIssuerToken } from "../../src/interfaces/IIssuerToken.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { IAttester } from "../../src/interfaces/IAttester.sol";
import { MockEAS } from "../mocks/MockEAS.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { TestConstants } from "./TestConstants.sol";

abstract contract DeployHelpers is TestConstants {
    function deployTokenImplementation() internal returns (address) {
        return address(new IssuerToken());
    }

    function deployFactory(address admin, address operator) internal returns (Factory factory, address implementation) {
        implementation = deployTokenImplementation();
        factory = new Factory(implementation, admin, operator);
    }

    function deployIssuerToken(address admin, address operator) internal returns (IssuerToken token) {
        address implementation = deployTokenImplementation();
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);
        token = IssuerToken(
            address(new ERC1967Proxy(implementation, abi.encodeCall(IIssuerToken.initialize, (params))))
        );
    }

    function deployDistribution(address admin, address operator)
        internal
        returns (Distribution distribution, MockToken paymentToken)
    {
        paymentToken = new MockToken("Mock Rupiah", "MIDR");
        address implementation = address(new Distribution());
        distribution = Distribution(
            address(
                new ERC1967Proxy(
                    implementation, abi.encodeCall(IDistribution.initialize, (address(paymentToken), admin, operator))
                )
            )
        );
    }

    function deployAttester(address admin, address operator)
        internal
        returns (Attester attester, MockEAS eas, bytes32 verificationSchema, bytes32 scoreSchema, bytes32 distributionSchema)
    {
        eas = new MockEAS();
        verificationSchema = keccak256("VerificationSchema");
        scoreSchema = keccak256("ScoreSchema");
        distributionSchema = keccak256("DistributionSchema");

        address implementation = address(new Attester());
        attester = Attester(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeCall(
                        IAttester.initialize,
                        (address(eas), verificationSchema, scoreSchema, distributionSchema, admin, operator)
                    )
                )
            )
        );
    }

    function defaultTokenParams(address admin, address operator)
        internal
        pure
        returns (IIssuerToken.InitParams memory)
    {
        return IIssuerToken.InitParams({
            issuerId: ISSUER_ID,
            tokenName: TOKEN_NAME,
            tokenSymbol: TOKEN_SYMBOL,
            maxSupply: MAX_SUPPLY,
            pricePerUnit: PRICE_PER_UNIT,
            profitSharingRatio: PROFIT_SHARING_RATIO,
            distributionPeriod: DISTRIBUTION_PERIOD,
            transferRestricted: true,
            admin: admin,
            operator: operator
        });
    }

    function defaultFactoryParams() internal pure returns (Factory.CreateIssuerTokenParams memory) {
        return Factory.CreateIssuerTokenParams({
            issuerId: ISSUER_ID,
            tokenName: TOKEN_NAME,
            tokenSymbol: TOKEN_SYMBOL,
            totalSupply: MAX_SUPPLY,
            pricePerUnit: PRICE_PER_UNIT,
            profitSharingRatio: PROFIT_SHARING_RATIO,
            distributionPeriod: DISTRIBUTION_PERIOD,
            transferRestricted: true
        });
    }

    function holderAmounts(address holderA, uint256 amountA, address holderB, uint256 amountB)
        internal
        pure
        returns (IDistribution.HolderAmount[] memory holders)
    {
        holders = new IDistribution.HolderAmount[](2);
        holders[0] = IDistribution.HolderAmount({ holderAddress: holderA, amount: amountA });
        holders[1] = IDistribution.HolderAmount({ holderAddress: holderB, amount: amountB });
    }

    function singleHolderAmount(address holder, uint256 amount)
        internal
        pure
        returns (IDistribution.HolderAmount[] memory holders)
    {
        holders = new IDistribution.HolderAmount[](1);
        holders[0] = IDistribution.HolderAmount({ holderAddress: holder, amount: amount });
    }
}
