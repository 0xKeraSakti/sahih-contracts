// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
        assertEq(terms.maxSupply, MAX_SUPPLY);
        assertEq(terms.circulatingSupply, 0);
        assertEq(terms.pricePerUnit, PRICE_PER_UNIT);
        assertEq(terms.distributionPeriod, DISTRIBUTION_PERIOD);
        assertTrue(terms.transferRestricted);
        assertTrue(terms.active);
    }

    /// @notice Issuer terms report the minted supply separately from the mintable cap
    function test_IssuerTermsTracksCirculatingSupplySeparately() public {
        vm.prank(operator);
        token.purchaseTokens(investorA, 400, "qris");

        IIssuerToken.IssuerTerms memory terms = token.getIssuerTerms();

        assertEq(terms.maxSupply, MAX_SUPPLY);
        assertEq(terms.circulatingSupply, 400);
    }

    /// @notice Initialization grants the admin and operator roles and nothing to outsiders
    function test_RolesGrantedOnInitialize() public view {
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), operator));
        assertFalse(token.hasRole(token.OPERATOR_ROLE(), outsider));
    }

    /// @notice A newly initialized token starts active
    function test_TokenStartsActive() public view {
        assertTrue(token.active());
    }

    /// @notice Reverts when initializing a token deployed outside the factory with an empty name
    function test_RevertWhen_InitializedWithEmptyTokenName() public {
        address implementation = deployTokenImplementation();
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);
        params.tokenName = "";

        vm.expectRevert(IssuerToken.EmptyTokenName.selector);
        new ERC1967Proxy(implementation, abi.encodeCall(IIssuerToken.initialize, (params)));
    }

    /// @notice Reverts when initializing a token deployed outside the factory with an empty symbol
    function test_RevertWhen_InitializedWithEmptyTokenSymbol() public {
        address implementation = deployTokenImplementation();
        IIssuerToken.InitParams memory params = defaultTokenParams(admin, operator);
        params.tokenSymbol = "";

        vm.expectRevert(IssuerToken.EmptyTokenSymbol.selector);
        new ERC1967Proxy(implementation, abi.encodeCall(IIssuerToken.initialize, (params)));
    }

    /// @notice Sukuk units are indivisible, so the token reports zero decimals
    function test_TokenHasZeroDecimals() public view {
        assertEq(token.decimals(), 0);
    }

    /// @notice The issuer's own wallet address is stored at initialization
    function test_IssuerWalletStoredOnInitialize() public view {
        assertEq(token.issuerWallet(), ISSUER_WALLET);
    }

    /// @notice An admin can rotate the issuer's wallet address
    function test_AdminUpdatesIssuerWallet() public {
        address newWallet = makeAddr("newIssuerWallet");

        vm.prank(admin);
        token.setIssuerWallet(newWallet);

        assertEq(token.issuerWallet(), newWallet);
    }

    /// @notice An operator can pause purchases without deactivating the issuer
    function test_OperatorPausesPurchases() public {
        vm.prank(operator);
        token.setPurchasePaused(true);

        assertTrue(token.purchasePaused());
        // Pausing purchases leaves the issuer itself active
        assertTrue(token.active());

        vm.prank(investorA);
        vm.expectRevert(IssuerToken.PurchasePaused.selector);
        token.purchaseTokens(investorA, 100, "qris");
    }

    /// @notice Purchases resume once the pause is lifted
    function test_PurchaseResumesAfterUnpause() public {
        vm.startPrank(operator);
        token.setPurchasePaused(true);
        token.setPurchasePaused(false);
        vm.stopPrank();

        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        assertEq(token.balanceOf(investorA), 100);
    }

    /// @notice Balances and circulating supply are read together in a single call
    function test_BalancesAtReadsHoldersAndSupplyTogether() public {
        vm.startPrank(operator);
        token.purchaseTokens(investorA, 300, "qris");
        token.purchaseTokens(investorB, 700, "qris");
        vm.stopPrank();

        address[] memory accounts = new address[](3);
        accounts[0] = investorA;
        accounts[1] = investorB;
        accounts[2] = outsider;

        (uint256[] memory balances, uint256 circulatingSupply) = token.balancesAt(accounts);

        assertEq(balances.length, 3);
        assertEq(balances[0], 300);
        assertEq(balances[1], 700);
        assertEq(balances[2], 0);
        assertEq(circulatingSupply, 1000);
    }

    /// @notice A payment that covers whole units exactly leaves no change
    function test_QuotePurchaseExactPayment() public view {
        (uint256 units, uint256 change) = token.quotePurchase(PRICE_PER_UNIT * 3);

        assertEq(units, 3);
        assertEq(change, 0);
    }

    /// @notice A payment that does not divide evenly rounds units down and reports the shortfall
    function test_QuotePurchaseRoundsDownAndReportsChange() public view {
        (uint256 units, uint256 change) = token.quotePurchase(PRICE_PER_UNIT * 2 + 1);

        assertEq(units, 2);
        assertEq(change, 1);
    }

    /// @notice A payment below the unit price buys nothing and is returned in full as change
    function test_QuotePurchaseBelowUnitPrice() public view {
        (uint256 units, uint256 change) = token.quotePurchase(PRICE_PER_UNIT - 1);

        assertEq(units, 0);
        assertEq(change, PRICE_PER_UNIT - 1);
    }

    /// @notice An admin can deactivate the issuer directly on the token
    function test_AdminSetsActiveStatus() public {
        vm.prank(admin);
        token.setActive(false);

        assertFalse(token.active());
    }

    /// @notice Purchases are blocked once the issuer is deactivated
    function test_RevertWhen_PurchasingFromInactiveIssuer() public {
        vm.prank(admin);
        token.setActive(false);

        vm.prank(investorA);
        vm.expectRevert(IssuerToken.IssuerInactive.selector);
        token.purchaseTokens(investorA, 100, "qris");
    }

    /// @notice Purchases resume once a deactivated issuer is reactivated
    function test_PurchaseResumesAfterReactivation() public {
        vm.startPrank(admin);
        token.setActive(false);
        token.setActive(true);
        vm.stopPrank();

        vm.prank(investorA);
        token.purchaseTokens(investorA, 100, "qris");

        assertEq(token.balanceOf(investorA), 100);
    }

    /// @notice Reverts when an account holding neither the factory nor admin role updates the active status
    function test_RevertWhen_UnauthorizedUpdatesActiveStatus() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IssuerToken.UnauthorizedStatusUpdate.selector, operator));
        token.setActive(false);
    }
}
