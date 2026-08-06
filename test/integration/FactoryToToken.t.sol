// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Factory } from "../../src/Factory.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { IIssuerToken } from "../../src/interfaces/IIssuerToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract FactoryToTokenTest is Test, DeployHelpers {
    Factory internal factory;
    address internal tokenImplementation;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal investorA = makeAddr("investorA");

    function setUp() public {
        (factory, tokenImplementation) = deployFactory(admin, operator);
    }

    function test_ProxyDeployedByFactoryIsUsableThroughInterface() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        IIssuerToken token = IIssuerToken(contractAddress);
        IIssuerToken.IssuerTerms memory terms = token.getIssuerTerms();

        assertEq(terms.totalSupply, MAX_SUPPLY);
        assertEq(terms.pricePerUnit, PRICE_PER_UNIT);
        assertEq(terms.profitSharingRatio, PROFIT_SHARING_RATIO);
        assertEq(token.remainingSupply(), MAX_SUPPLY);

        vm.prank(investorA);
        token.purchaseTokens(investorA, 500, "qris");

        assertEq(IssuerToken(contractAddress).balanceOf(investorA), 500);
        assertEq(token.remainingSupply(), MAX_SUPPLY - 500);
    }

    function test_OperatorRoleFromFactoryIsConsistentOnDeployedToken() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        IssuerToken token = IssuerToken(contractAddress);

        vm.prank(operator);
        token.purchaseTokens(investorA, 100, "bank_transfer");

        assertEq(token.balanceOf(investorA), 100);
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), operator));
        assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
    }

    function test_RotatedTokenRolesApplyToNextDeployment() public {
        address newOperator = makeAddr("newOperator");
        Factory.CreateIssuerTokenParams memory second = defaultFactoryParams();
        second.issuerId = ISSUER_ID_SECOND;

        vm.prank(admin);
        factory.setTokenRoles(admin, newOperator);

        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(second);

        IssuerToken token = IssuerToken(contractAddress);
        assertTrue(token.hasRole(token.OPERATOR_ROLE(), newOperator));
        assertFalse(token.hasRole(token.OPERATOR_ROLE(), operator));
    }

    function test_EachIssuerGetsIsolatedTokenState() public {
        Factory.CreateIssuerTokenParams memory second = defaultFactoryParams();
        second.issuerId = ISSUER_ID_SECOND;
        second.tokenSymbol = "SHUMKM2";

        vm.startPrank(operator);
        (address firstToken,) = factory.createIssuerToken(defaultFactoryParams());
        (address secondToken,) = factory.createIssuerToken(second);
        vm.stopPrank();

        vm.prank(investorA);
        IIssuerToken(firstToken).purchaseTokens(investorA, 300, "qris");

        assertEq(IssuerToken(firstToken).balanceOf(investorA), 300);
        assertEq(IssuerToken(secondToken).balanceOf(investorA), 0);
        assertEq(IssuerToken(secondToken).issuerId(), ISSUER_ID_SECOND);
    }
}
