// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Factory } from "../../src/Factory.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

/// @title FactoryTest
/// @author Sahih Contracts
/// @notice Unit tests for the Factory contract
contract FactoryTest is Test, DeployHelpers {
    Factory internal factory;
    address internal tokenImplementation;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal outsider = makeAddr("outsider");

    /// @notice Deploys a fresh Factory and token implementation before each test
    function setUp() public {
        (factory, tokenImplementation) = deployFactory(admin, operator);
    }

    /// @notice Creating an issuer token deploys a usable proxy registered under its issuer id
    function test_CreateIssuerTokenDeploysProxy() public {
        vm.prank(operator);
        (address contractAddress, uint256 deployedAt) = factory.createIssuerToken(defaultFactoryParams());

        assertTrue(contractAddress != address(0));
        assertEq(deployedAt, block.timestamp);
        assertEq(factory.issuerContracts(ISSUER_ID), contractAddress);
        assertEq(factory.totalIssuers(), 1);
        assertEq(IssuerToken(contractAddress).issuerId(), ISSUER_ID);
    }

    /// @notice The deployed issuer token grants the configured admin and operator roles
    function test_CreateIssuerTokenGrantsConfiguredRoles() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        IssuerToken token = IssuerToken(contractAddress);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), operator));
    }

    /// @notice Reverts when a non-operator attempts to create an issuer token
    function test_RevertWhen_NonOperatorCreatesIssuerToken() public {
        bytes32 operatorRole = factory.OPERATOR_ROLE();
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, operatorRole)
        );
        factory.createIssuerToken(defaultFactoryParams());
    }

    /// @notice Reverts when attempting to register an issuer id that already exists
    function test_RevertWhen_IssuerAlreadyRegistered() public {
        vm.startPrank(operator);
        factory.createIssuerToken(defaultFactoryParams());

        vm.expectRevert(abi.encodeWithSelector(Factory.IssuerAlreadyRegistered.selector, ISSUER_ID));
        factory.createIssuerToken(defaultFactoryParams());
        vm.stopPrank();
    }

    /// @notice Reverts when the profit sharing ratio is zero
    function test_RevertWhen_ProfitSharingRatioIsZero() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.profitSharingRatio = 0;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidProfitSharingRatio.selector, 0));
        factory.createIssuerToken(params);
    }

    /// @notice Reverts when the profit sharing ratio exceeds the maximum allowed value
    function test_RevertWhen_ProfitSharingRatioAboveMaximum() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.profitSharingRatio = 10_001;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidProfitSharingRatio.selector, 10_001));
        factory.createIssuerToken(params);
    }

    /// @notice Reverts when the issuer id is an empty string
    function test_RevertWhen_IssuerIdIsEmpty() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.issuerId = "";

        vm.prank(operator);
        vm.expectRevert(Factory.EmptyIssuerId.selector);
        factory.createIssuerToken(params);
    }

    /// @notice Reverts when the token name is an empty string
    function test_RevertWhen_TokenNameIsEmpty() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.tokenName = "";

        vm.prank(operator);
        vm.expectRevert(Factory.EmptyTokenName.selector);
        factory.createIssuerToken(params);
    }

    /// @notice Reverts when the token symbol is an empty string
    function test_RevertWhen_TokenSymbolIsEmpty() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.tokenSymbol = "";

        vm.prank(operator);
        vm.expectRevert(Factory.EmptyTokenSymbol.selector);
        factory.createIssuerToken(params);
    }

    /// @notice Fetching an issuer contract returns its stored address, deployment time, and active status
    function test_GetIssuerContractReturnsMetadata() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        (address stored, uint256 deployedAt, bool active) = factory.getIssuerContract(ISSUER_ID);

        assertEq(stored, contractAddress);
        assertEq(deployedAt, block.timestamp);
        assertTrue(active);
    }

    /// @notice Reverts when querying an issuer id that was never registered
    function test_RevertWhen_IssuerNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Factory.IssuerNotFound.selector, ISSUER_ID_SECOND));
        factory.getIssuerContract(ISSUER_ID_SECOND);
    }

    /// @notice Listing all issuers returns correctly paginated pages, including an empty final page
    function test_ListAllIssuersPaginates() public {
        Factory.CreateIssuerTokenParams memory second = defaultFactoryParams();
        second.issuerId = ISSUER_ID_SECOND;

        vm.startPrank(operator);
        factory.createIssuerToken(defaultFactoryParams());
        factory.createIssuerToken(second);
        vm.stopPrank();

        (Factory.IssuerSummary[] memory firstPage, uint256 totalCount) = factory.listAllIssuers(1, 1);
        assertEq(totalCount, 2);
        assertEq(firstPage.length, 1);
        assertEq(firstPage[0].issuerId, ISSUER_ID);

        (Factory.IssuerSummary[] memory secondPage,) = factory.listAllIssuers(2, 1);
        assertEq(secondPage.length, 1);
        assertEq(secondPage[0].issuerId, ISSUER_ID_SECOND);

        (Factory.IssuerSummary[] memory emptyPage,) = factory.listAllIssuers(3, 1);
        assertEq(emptyPage.length, 0);
    }

    /// @notice Reverts when the pagination parameters are invalid
    function test_RevertWhen_PaginationIsInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidPagination.selector, 0, 20));
        factory.listAllIssuers(0, 20);
    }

    /// @notice An admin can update the token implementation used for future deployments
    function test_AdminUpdatesTokenImplementation() public {
        address newImplementation = deployTokenImplementation();

        vm.prank(admin);
        factory.setTokenImplementation(newImplementation);

        assertEq(factory.tokenImplementation(), newImplementation);
    }

    /// @notice Reverts when a non-admin attempts to update the token implementation
    function test_RevertWhen_NonAdminUpdatesTokenImplementation() public {
        address newImplementation = deployTokenImplementation();
        bytes32 adminRole = factory.ADMIN_ROLE();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, adminRole)
        );
        factory.setTokenImplementation(newImplementation);
    }

    /// @notice An admin can deactivate a registered issuer, and the status reaches the deployed token
    function test_AdminUpdatesIssuerStatus() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        vm.prank(admin);
        factory.setIssuerStatus(ISSUER_ID, false);

        (,, bool active) = factory.getIssuerContract(ISSUER_ID);
        assertFalse(active);
        assertFalse(IssuerToken(contractAddress).active());
    }

    /// @notice A deployed contract address resolves back to its issuer metadata
    function test_GetIssuerMetaResolvesAddressToIssuerId() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        Factory.IssuerMeta memory meta = factory.getIssuerMeta(contractAddress);

        assertEq(meta.issuerId, ISSUER_ID);
        assertEq(meta.deployedAt, block.timestamp);
        assertTrue(meta.active);
    }

    /// @notice Reverts when resolving an address that was never deployed by this factory
    function test_RevertWhen_IssuerContractNotFound() public {
        address stranger = makeAddr("stranger");

        vm.expectRevert(abi.encodeWithSelector(Factory.IssuerContractNotFound.selector, stranger));
        factory.getIssuerMeta(stranger);
    }

    /// @notice The issuer's own wallet address is carried through to the deployed token
    function test_IssuerWalletPropagatesToDeployedToken() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        assertEq(IssuerToken(contractAddress).issuerWallet(), ISSUER_WALLET);
    }

    /// @notice Reverts when creating an issuer token without an issuer wallet address
    function test_RevertWhen_IssuerWalletIsZero() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.issuerWallet = address(0);

        vm.prank(operator);
        vm.expectRevert(Factory.ZeroAddress.selector);
        factory.createIssuerToken(params);
    }

    /// @notice The Factory holds the role that lets it propagate status changes to the tokens it deploys
    function test_FactoryHoldsFactoryRoleOnDeployedToken() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        IssuerToken token = IssuerToken(contractAddress);
        assertTrue(token.hasRole(token.FACTORY_ROLE(), address(factory)));
    }
}
