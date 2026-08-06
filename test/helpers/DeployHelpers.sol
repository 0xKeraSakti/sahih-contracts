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

/// @title DeployHelpers
/// @author Sahih Contracts
/// @notice Shared deployment and fixture-building helpers used across the test suite
abstract contract DeployHelpers is TestConstants {
    /// @notice Deploys a bare IssuerToken implementation contract
    /// @return Address of the deployed implementation
    function deployTokenImplementation() internal returns (address) {
        return address(new IssuerToken());
    }

    /// @notice Deploys a Factory wired to a fresh token implementation
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    /// @return factory The deployed Factory
    /// @return implementation Address of the token implementation used by the factory
    function deployFactory(
        address admin,
        address operator
    ) internal returns (Factory factory, address implementation) {
        implementation = deployTokenImplementation();
        factory = new Factory(implementation, admin, operator);
    }

    /// @notice Deploys and initializes an IssuerToken proxy with default terms
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    /// @return token The deployed and initialized IssuerToken proxy
    function deployIssuerToken(
        address admin,
        address operator
    ) internal returns (IssuerToken token) {
        address implementation = deployTokenImplementation();
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);
        token =
            IssuerToken(address(new ERC1967Proxy(implementation, abi.encodeCall(IIssuerToken.initialize, (params)))));
    }

    /// @notice Deploys and initializes a Distribution proxy with a fresh mock payment token
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    /// @return distribution The deployed and initialized Distribution proxy
    /// @return paymentToken The mock ERC20 payment token used by the distribution
    function deployDistribution(
        address admin,
        address operator
    ) internal returns (Distribution distribution, MockToken paymentToken) {
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

    /// @notice Deploys and initializes an Attester proxy with a fresh mock EAS and sample schemas
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    /// @return attester The deployed and initialized Attester proxy
    /// @return eas The mock EAS used by the attester
    /// @return verificationSchema Sample verification schema UID
    /// @return scoreSchema Sample score schema UID
    /// @return distributionSchema Sample distribution schema UID
    function deployAttester(
        address admin,
        address operator
    )
        internal
        returns (
            Attester attester,
            MockEAS eas,
            bytes32 verificationSchema,
            bytes32 scoreSchema,
            bytes32 distributionSchema
        )
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

    /// @notice Builds default IssuerToken initialization parameters
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    /// @return Default issuer token initialization parameters
    function defaultTokenParams(
        address admin,
        address operator
    ) internal pure returns (IIssuerToken.InitParams memory) {
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

    /// @notice Builds default Factory issuer-token creation parameters
    /// @return Default issuer token creation parameters
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

    /// @notice Builds a two-holder distribution amount array
    /// @param holderA Address of the first holder
    /// @param amountA Amount to pay the first holder
    /// @param holderB Address of the second holder
    /// @param amountB Amount to pay the second holder
    /// @return holders The two-holder amount array
    function holderAmounts(
        address holderA,
        uint256 amountA,
        address holderB,
        uint256 amountB
    ) internal pure returns (IDistribution.HolderAmount[] memory holders) {
        holders = new IDistribution.HolderAmount[](2);
        holders[0] = IDistribution.HolderAmount({ holderAddress: holderA, amount: amountA });
        holders[1] = IDistribution.HolderAmount({ holderAddress: holderB, amount: amountB });
    }

    /// @notice Builds a single-holder distribution amount array
    /// @param holder Address of the holder
    /// @param amount Amount to pay the holder
    /// @return holders The single-holder amount array
    function singleHolderAmount(
        address holder,
        uint256 amount
    ) internal pure returns (IDistribution.HolderAmount[] memory holders) {
        holders = new IDistribution.HolderAmount[](1);
        holders[0] = IDistribution.HolderAmount({ holderAddress: holder, amount: amount });
    }
}
