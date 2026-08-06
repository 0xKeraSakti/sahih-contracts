// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { IIssuerToken } from "../../src/interfaces/IIssuerToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

/// @title IssuerTokenTest
/// @author Sahih Contracts
/// @notice Unit tests for the IssuerToken contract
contract IssuerTokenTest is Test, DeployHelpers {
    IssuerToken internal token;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal investorA = makeAddr("investorA");
    address internal investorB = makeAddr("investorB");
    address internal outsider = makeAddr("outsider");

    /// @notice Deploys a fresh IssuerToken before each test
    function setUp() public {
        token = deployIssuerToken(admin, operator);
    }

    /// @notice Reverts when initialize is called a second time on an already-initialized token
    function test_RevertWhen_InitializeCalledTwice() public {
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize(params);
    }

    /// @notice An investor can purchase tokens directly for themselves
    function test_PurchaseTokensByInvestor() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        assertEq(token.balanceOf(investorA), 100);
        assertEq(token.totalSupply(), 100);
        assertEq(token.remainingSupply(), MAX_SUPPLY - 100);
    }

    /// @notice An operator can purchase tokens on behalf of an investor
    function test_PurchaseTokensByOperatorOnBehalfOfInvestor() public {
        vm.prank(operator);
        token.purchaseTokens(investorA, 250, "bank_transfer");

        assertEq(token.balanceOf(investorA), 250);
    }

    /// @notice Reverts when an unauthorized third party attempts to purchase on behalf of another investor
    function test_RevertWhen_PurchaseByUnauthorizedThirdParty() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IssuerToken.UnauthorizedPurchaser.selector, outsider, investorA));
        token.purchaseTokens(investorA, 100, "qris");
    }

    /// @notice Reverts when the purchase amount is zero
    function test_RevertWhen_PurchaseAmountIsZero() public {
        vm.prank(investorA);
        vm.expectRevert(IssuerToken.ZeroAmount.selector);
        token.purchaseTokens(investorA, 0, "qris");
    }

    /// @notice Reverts when a purchase would exceed the remaining token supply
    function test_RevertWhen_PurchaseExceedsRemainingSupply() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, MAX_SUPPLY - 10, "qris");

        vm.prank(investorB);
        vm.expectRevert(abi.encodeWithSelector(IssuerToken.SupplyExceeded.selector, 11, 10));
        token.purchaseTokens(investorB, 11, "qris");
    }

    /// @notice Reverts when transferring to an address that is not whitelisted while transfers are restricted
    function test_RevertWhen_TransferToNonWhitelistedAddress() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(investorA);
        vm.expectRevert(IssuerToken.TransferRestricted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(investorB, 10);
    }

    /// @notice Transfers succeed when the recipient has been added to the transfer whitelist
    function test_TransferAllowedToWhitelistedAddress() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(admin);
        token.setTransferWhitelist(investorB, true);

        vm.prank(investorA);
        assertTrue(token.transfer(investorB, 40));

        assertEq(token.balanceOf(investorA), 60);
        assertEq(token.balanceOf(investorB), 40);
    }

    /// @notice Transfers succeed to any address once the transfer restriction is disabled
    function test_TransferAllowedWhenRestrictionDisabled() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(admin);
        token.setTransferRestricted(false);

        vm.prank(investorA);
        assertTrue(token.transfer(investorB, 25));

        assertEq(token.balanceOf(investorB), 25);
    }

    /// @notice Reverts when transferFrom is used by a spender sending to a non-whitelisted recipient
    function test_RevertWhen_TransferFromNonWhitelistedSpender() public {
        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        vm.prank(investorA);
        token.approve(outsider, 50);

        vm.prank(outsider);
        vm.expectRevert(IssuerToken.TransferRestricted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(investorA, outsider, 50);
    }

    /// @notice Reverts when a non-admin attempts to update the transfer whitelist
    function test_RevertWhen_NonAdminUpdatesWhitelist() public {
        bytes32 adminRole = token.ADMIN_ROLE();
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, adminRole)
        );
        token.setTransferWhitelist(investorB, true);
    }

    /// @notice Reverts when a non-admin attempts to upgrade the contract
    function test_RevertWhen_NonAdminUpgrades() public {
        address newImplementation = deployTokenImplementation();
        bytes32 adminRole = token.ADMIN_ROLE();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, adminRole)
        );
        token.upgradeToAndCall(newImplementation, "");
    }

    /// @notice An admin can grant the operator role to a new address and revoke it from the old one
    function test_AdminCanRotateOperatorRole() public {
        address newOperator = makeAddr("newOperator");

        vm.startPrank(admin);
        token.grantRole(token.OPERATOR_ROLE(), newOperator);
        token.revokeRole(token.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        assertTrue(token.hasRole(token.OPERATOR_ROLE(), newOperator));
        assertFalse(token.hasRole(token.OPERATOR_ROLE(), operator));
    }

    /// @notice Reverts when the implementation contract itself is initialized directly
    function test_RevertWhen_ImplementationInitializedDirectly() public {
        IssuerToken implementation = IssuerToken(deployTokenImplementation());
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(params);
    }

    /// @notice Initialization stores the issuer terms and metadata exactly as provided
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

    /// @notice Initialization grants the admin and operator roles and nothing to outsiders
    function test_RolesGrantedOnInitialize() public view {
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), operator));
        assertFalse(token.hasRole(token.OPERATOR_ROLE(), outsider));
    }
}
