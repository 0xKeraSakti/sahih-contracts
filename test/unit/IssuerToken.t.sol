// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { IIssuerToken } from "../../src/interfaces/IIssuerToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract IssuerTokenTest is Test, DeployHelpers {
    IssuerToken internal token;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal investorA = makeAddr("investorA");
    address internal investorB = makeAddr("investorB");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        token = deployIssuerToken(admin, operator);
    }

    function test_InitializeStoresTerms() public view {
        IIssuerToken.IssuerTerms memory terms = token.getIssuerTerms();

        assertEq(token.issuerId(), ISSUER_ID);
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(terms.profitSharingRatio, PROFIT_SHARING_RATIO);
        assertEq(terms.totalSupply, MAX_SUPPLY);
        assertEq(terms.pricePerUnit, PRICE_PER_UNIT);
        assertEq(terms.distributionPeriod, DISTRIBUTION_PERIOD);
        assertTrue(terms.transferRestricted);
    }

    function test_RolesGrantedOnInitialize() public view {
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), operator));
        assertFalse(token.hasRole(token.OPERATOR_ROLE(), outsider));
    }

    function test_RevertWhen_InitializeCalledTwice() public {
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize(params);
    }

    function test_PurchaseTokensByInvestor() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        assertEq(token.balanceOf(investorA), 100);
        assertEq(token.totalSupply(), 100);
        assertEq(token.remainingSupply(), MAX_SUPPLY - 100);
    }

    function test_PurchaseTokensByOperatorOnBehalfOfInvestor() public {
        vm.prank(operator);
        token.purchaseTokens(investorA, 250, "bank_transfer");

        assertEq(token.balanceOf(investorA), 250);
    }

    function test_RevertWhen_PurchaseByUnauthorizedThirdParty() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IssuerToken.UnauthorizedPurchaser.selector, outsider, investorA)
        );
        token.purchaseTokens(investorA, 100, "qris");
    }

    function test_RevertWhen_PurchaseAmountIsZero() public {
        vm.prank(investorA);
        vm.expectRevert(IssuerToken.ZeroAmount.selector);
        token.purchaseTokens(investorA, 0, "qris");
    }

    function test_RevertWhen_PurchaseExceedsRemainingSupply() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, MAX_SUPPLY - 10, "qris");

        vm.prank(investorB);
        vm.expectRevert(abi.encodeWithSelector(IssuerToken.SupplyExceeded.selector, 11, 10));
        token.purchaseTokens(investorB, 11, "qris");
    }

    function test_RevertWhen_TransferToNonWhitelistedAddress() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(investorA);
        vm.expectRevert(IssuerToken.TransferRestricted.selector);
        token.transfer(investorB, 10);
    }

    function test_TransferAllowedToWhitelistedAddress() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(admin);
        token.setTransferWhitelist(investorB, true);

        vm.prank(investorA);
        token.transfer(investorB, 40);

        assertEq(token.balanceOf(investorA), 60);
        assertEq(token.balanceOf(investorB), 40);
    }

    function test_TransferAllowedWhenRestrictionDisabled() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(admin);
        token.setTransferRestricted(false);

        vm.prank(investorA);
        token.transfer(investorB, 25);

        assertEq(token.balanceOf(investorB), 25);
    }

    function test_RevertWhen_TransferFromNonWhitelistedSpender() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(investorA);
        token.approve(outsider, 50);

        vm.prank(outsider);
        vm.expectRevert(IssuerToken.TransferRestricted.selector);
        token.transferFrom(investorA, outsider, 50);
    }

    function test_RevertWhen_NonAdminUpdatesWhitelist() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, token.ADMIN_ROLE()
            )
        );
        token.setTransferWhitelist(investorB, true);
    }

    function test_RevertWhen_NonAdminUpgrades() public {
        address newImplementation = deployTokenImplementation();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, token.ADMIN_ROLE()
            )
        );
        token.upgradeToAndCall(newImplementation, "");
    }

    function test_AdminCanRotateOperatorRole() public {
        address newOperator = makeAddr("newOperator");

        vm.startPrank(admin);
        token.grantRole(token.OPERATOR_ROLE(), newOperator);
        token.revokeRole(token.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        assertTrue(token.hasRole(token.OPERATOR_ROLE(), newOperator));
        assertFalse(token.hasRole(token.OPERATOR_ROLE(), operator));
    }

    function test_RevertWhen_ImplementationInitializedDirectly() public {
        IssuerToken implementation = IssuerToken(deployTokenImplementation());
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(params);
    }
}
