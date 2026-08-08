// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Factory } from "../../src/Factory.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { Distribution } from "../../src/Distribution.sol";
import { IIssuerToken } from "../../src/interfaces/IIssuerToken.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { IssuerTokenV2 } from "../mocks/IssuerTokenV2.sol";
import { DemoPaymentToken } from "../../src/DemoPaymentToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

/// @title UpgradeFlowTest
/// @author Sahih Contracts
/// @notice Integration tests covering UUPS upgrade flows for IssuerToken and Distribution
contract UpgradeFlowTest is Test, DeployHelpers {
    Factory internal factory;
    Distribution internal distribution;
    DemoPaymentToken internal paymentToken;
    IssuerToken internal token;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal investorA = makeAddr("investorA");
    address internal investorB = makeAddr("investorB");

    /// @notice Deploys Factory and Distribution, creates an issuer token, funds it, and records a prior distribution before each test
    function setUp() public {
        (factory,) = deployFactory(admin, operator);
        (distribution, paymentToken) = deployDistribution(admin, operator);
        paymentToken.mint(address(distribution), PAYMENT_TOKEN_FUNDING);

        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());
        token = IssuerToken(contractAddress);

        vm.prank(investorA);
        token.purchaseTokens(investorA, 300, "qris");

        vm.prank(investorB);
        token.purchaseTokens(investorB, 700, "qris");

        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 127_500, investorB, 297_500);
        vm.prank(operator);
        distribution.recordDistribution(address(token), PERIOD_W32, holders, 425_000, CALCULATION_REF_HASH);
    }

    /// @notice All existing IssuerToken state is preserved after upgrading to the V2 implementation
    function test_TokenStatePreservedAfterUpgrade() public {
        address newImplementation = address(new IssuerTokenV2());

        vm.prank(admin);
        token.upgradeToAndCall(newImplementation, "");

        IssuerTokenV2 upgraded = IssuerTokenV2(address(token));

        assertEq(upgraded.issuerId(), ISSUER_ID);
        assertEq(upgraded.balanceOf(investorA), 300);
        assertEq(upgraded.balanceOf(investorB), 700);
        assertEq(upgraded.totalSupply(), 1000);
        assertEq(upgraded.maxSupply(), MAX_SUPPLY);
        assertEq(upgraded.pricePerUnit(), PRICE_PER_UNIT);
        assertEq(upgraded.profitSharingRatio(), PROFIT_SHARING_RATIO);
        assertTrue(upgraded.transferRestricted());
        assertTrue(upgraded.hasRole(upgraded.ADMIN_ROLE(), admin));
        assertTrue(upgraded.hasRole(upgraded.OPERATOR_ROLE(), operator));
    }

    /// @notice New functions introduced by the V2 implementation are usable after the upgrade
    function test_NewFunctionUsableAfterUpgrade() public {
        address newImplementation = address(new IssuerTokenV2());

        vm.prank(admin);
        token.upgradeToAndCall(newImplementation, "");

        IssuerTokenV2 upgraded = IssuerTokenV2(address(token));

        vm.prank(admin);
        upgraded.setSecondaryMarketFee(150);

        assertEq(upgraded.secondaryMarketFeeBps(), 150);
        assertEq(upgraded.VERSION(), "v2");
    }

    /// @notice Pre-existing behavior such as transfer restrictions and purchasing still works correctly after the upgrade
    function test_ExistingBehaviorStillEnforcedAfterUpgrade() public {
        address newImplementation = address(new IssuerTokenV2());

        vm.prank(admin);
        token.upgradeToAndCall(newImplementation, "");

        IssuerTokenV2 upgraded = IssuerTokenV2(address(token));

        vm.prank(investorA);
        vm.expectRevert(IssuerToken.TransferRestricted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        upgraded.transfer(investorB, 10);

        vm.prank(investorA);
        upgraded.purchaseTokens(investorA, 100, "qris");
        assertEq(upgraded.balanceOf(investorA), 400);
    }

    /// @notice Reverts when initialize is called again on the token after it has been upgraded
    function test_RevertWhen_InitializeCalledAfterUpgrade() public {
        address newImplementation = address(new IssuerTokenV2());

        vm.prank(admin);
        token.upgradeToAndCall(newImplementation, "");

        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        IssuerTokenV2(address(token)).initialize(params);
    }

    /// @notice Reverts when an operator, rather than an admin, attempts to upgrade the token
    function test_RevertWhen_OperatorUpgradesToken() public {
        address newImplementation = address(new IssuerTokenV2());
        bytes32 adminRole = token.ADMIN_ROLE();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, adminRole)
        );
        token.upgradeToAndCall(newImplementation, "");
    }

    /// @notice All existing Distribution state is preserved after upgrading the Distribution implementation
    function test_DistributionStatePreservedAfterUpgrade() public {
        address newImplementation = address(new Distribution());

        vm.prank(admin);
        distribution.upgradeToAndCall(newImplementation, "");

        IDistribution.DistributionRecord memory record = distribution.getDistributionRecord(address(token), PERIOD_W32);

        assertEq(record.totalAmount, 425_000);
        assertTrue(record.recorded);
        assertEq(distribution.getInvestorDistributions(investorA).length, 1);
        assertEq(address(distribution.paymentToken()), address(paymentToken));
    }
}
