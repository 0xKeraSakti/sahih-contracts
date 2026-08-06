// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Factory } from "../../src/Factory.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract FactoryTest is Test, DeployHelpers {
    Factory internal factory;
    address internal tokenImplementation;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        (factory, tokenImplementation) = deployFactory(admin, operator);
    }

    function test_CreateIssuerTokenDeploysProxy() public {
        vm.prank(operator);
        (address contractAddress, uint256 deployedAt) = factory.createIssuerToken(defaultFactoryParams());

        assertTrue(contractAddress != address(0));
        assertEq(deployedAt, block.timestamp);
        assertEq(factory.issuerContracts(ISSUER_ID), contractAddress);
        assertEq(factory.totalIssuers(), 1);
        assertEq(IssuerToken(contractAddress).issuerId(), ISSUER_ID);
    }

    function test_CreateIssuerTokenGrantsConfiguredRoles() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        IssuerToken token = IssuerToken(contractAddress);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), operator));
    }

    function test_RevertWhen_NonOperatorCreatesIssuerToken() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, factory.OPERATOR_ROLE()
            )
        );
        factory.createIssuerToken(defaultFactoryParams());
    }

    function test_RevertWhen_IssuerAlreadyRegistered() public {
        vm.startPrank(operator);
        factory.createIssuerToken(defaultFactoryParams());

        vm.expectRevert(abi.encodeWithSelector(Factory.IssuerAlreadyRegistered.selector, ISSUER_ID));
        factory.createIssuerToken(defaultFactoryParams());
        vm.stopPrank();
    }

    function test_RevertWhen_ProfitSharingRatioIsZero() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.profitSharingRatio = 0;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidProfitSharingRatio.selector, 0));
        factory.createIssuerToken(params);
    }

    function test_RevertWhen_ProfitSharingRatioAboveMaximum() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.profitSharingRatio = 10_001;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidProfitSharingRatio.selector, 10_001));
        factory.createIssuerToken(params);
    }

    function test_RevertWhen_IssuerIdIsEmpty() public {
        Factory.CreateIssuerTokenParams memory params = defaultFactoryParams();
        params.issuerId = "";

        vm.prank(operator);
        vm.expectRevert(Factory.EmptyIssuerId.selector);
        factory.createIssuerToken(params);
    }

    function test_GetIssuerContractReturnsMetadata() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        (address stored, uint256 deployedAt, bool active) = factory.getIssuerContract(ISSUER_ID);

        assertEq(stored, contractAddress);
        assertEq(deployedAt, block.timestamp);
        assertTrue(active);
    }

    function test_RevertWhen_IssuerNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Factory.IssuerNotFound.selector, ISSUER_ID_SECOND));
        factory.getIssuerContract(ISSUER_ID_SECOND);
    }

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

    function test_RevertWhen_PaginationIsInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidPagination.selector, 0, 20));
        factory.listAllIssuers(0, 20);
    }

    function test_AdminUpdatesTokenImplementation() public {
        address newImplementation = deployTokenImplementation();

        vm.prank(admin);
        factory.setTokenImplementation(newImplementation);

        assertEq(factory.tokenImplementation(), newImplementation);
    }

    function test_RevertWhen_NonAdminUpdatesTokenImplementation() public {
        address newImplementation = deployTokenImplementation();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, factory.ADMIN_ROLE()
            )
        );
        factory.setTokenImplementation(newImplementation);
    }

    function test_AdminUpdatesIssuerStatus() public {
        vm.prank(operator);
        factory.createIssuerToken(defaultFactoryParams());

        vm.prank(admin);
        factory.setIssuerStatus(ISSUER_ID, false);

        (,, bool active) = factory.getIssuerContract(ISSUER_ID);
        assertFalse(active);
    }
}
