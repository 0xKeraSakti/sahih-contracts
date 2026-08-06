// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Distribution } from "../../src/Distribution.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract DistributionTest is Test, DeployHelpers {
    Distribution internal distribution;
    MockToken internal paymentToken;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal outsider = makeAddr("outsider");
    address internal issuerContract = makeAddr("issuerContract");
    address internal investorA = makeAddr("investorA");
    address internal investorB = makeAddr("investorB");

    function setUp() public {
        (distribution, paymentToken) = deployDistribution(admin, operator);
        paymentToken.mint(address(distribution), PAYMENT_TOKEN_FUNDING);
    }

    function test_RecordDistributionTransfersToHolders() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 127_500, investorB, 297_500);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 425_000, CALCULATION_REF_HASH);

        assertEq(paymentToken.balanceOf(investorA), 127_500);
        assertEq(paymentToken.balanceOf(investorB), 297_500);
        assertEq(paymentToken.balanceOf(address(distribution)), PAYMENT_TOKEN_FUNDING - 425_000);
    }

    function test_RecordDistributionStoresRecord() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, investorB, 200);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 300, CALCULATION_REF_HASH);

        IDistribution.DistributionRecord memory record =
            distribution.getDistributionRecord(issuerContract, PERIOD_W32);

        assertEq(record.period, PERIOD_W32);
        assertEq(record.totalAmount, 300);
        assertEq(record.distributedAt, block.timestamp);
        assertEq(record.calculationRefHash, CALCULATION_REF_HASH);
        assertTrue(record.recorded);
    }

    function test_RecordDistributionEmitsDistributed() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 500);

        vm.expectEmit(true, false, false, true, address(distribution));
        emit IDistribution.Distributed(issuerContract, PERIOD_W32, 500, block.timestamp);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 500, CALCULATION_REF_HASH);
    }

    function test_RecordDistributionAllowsZeroTotal() public {
        IDistribution.HolderAmount[] memory holders = new IDistribution.HolderAmount[](0);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 0, CALCULATION_REF_HASH);

        IDistribution.DistributionRecord memory record =
            distribution.getDistributionRecord(issuerContract, PERIOD_W32);

        assertTrue(record.recorded);
        assertEq(record.totalAmount, 0);
    }

    function test_RevertWhen_TotalDoesNotMatchBreakdown() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, investorB, 200);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Distribution.DistributionTotalMismatch.selector, 500, 300));
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 500, CALCULATION_REF_HASH);
    }

    function test_RevertWhen_PeriodAlreadyRecorded() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(Distribution.PeriodAlreadyRecorded.selector, issuerContract, PERIOD_W32)
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();
    }

    function test_RevertWhen_ContractBalanceInsufficient() public {
        uint256 amount = PAYMENT_TOKEN_FUNDING + 1;
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, amount);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(Distribution.InsufficientBalance.selector, amount, PAYMENT_TOKEN_FUNDING)
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, amount, CALCULATION_REF_HASH);
    }

    function test_RevertWhen_NonOperatorRecordsDistribution() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, distribution.OPERATOR_ROLE()
            )
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
    }

    function test_RevertWhen_HolderCountExceedsMaximum() public {
        uint256 count = distribution.MAX_HOLDERS_PER_DISTRIBUTION() + 1;
        IDistribution.HolderAmount[] memory holders = new IDistribution.HolderAmount[](count);
        for (uint256 i = 0; i < count; i++) {
            holders[i] = IDistribution.HolderAmount({ holderAddress: address(uint160(i + 1)), amount: 1 });
        }

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                Distribution.TooManyHolders.selector, count, distribution.MAX_HOLDERS_PER_DISTRIBUTION()
            )
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, count, CALCULATION_REF_HASH);
    }

    function test_RevertWhen_HolderAddressIsZero() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, address(0), 200);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Distribution.InvalidHolder.selector, 1));
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 300, CALCULATION_REF_HASH);
    }

    function test_RevertWhen_PeriodIsEmpty() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.prank(operator);
        vm.expectRevert(Distribution.EmptyPeriod.selector);
        distribution.recordDistribution(issuerContract, "", holders, 100, CALCULATION_REF_HASH);
    }

    function test_GetDistributionHistoryFiltersByRange() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W31, holders, 100, CALCULATION_REF_HASH);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
        distribution.recordDistribution(issuerContract, PERIOD_W33, holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();

        IDistribution.PeriodSummary[] memory history =
            distribution.getDistributionHistory(issuerContract, PERIOD_W31, PERIOD_W32);

        assertEq(history.length, 2);
        assertEq(history[0].period, PERIOD_W31);
        assertEq(history[1].period, PERIOD_W32);
    }

    function test_GetInvestorDistributions() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, investorB, 200);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W31, holders, 300, CALCULATION_REF_HASH);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 300, CALCULATION_REF_HASH);
        vm.stopPrank();

        IDistribution.InvestorDistribution[] memory received = distribution.getInvestorDistributions(investorA);

        assertEq(received.length, 2);
        assertEq(received[0].issuerContract, issuerContract);
        assertEq(received[0].period, PERIOD_W31);
        assertEq(received[0].amount, 100);
        assertEq(received[1].period, PERIOD_W32);
    }

    function test_AdminUpdatesPaymentToken() public {
        MockToken newToken = new MockToken("Mock Rupiah 2", "MIDR2");

        vm.prank(admin);
        distribution.setPaymentToken(address(newToken));

        assertEq(address(distribution.paymentToken()), address(newToken));
    }

    function test_RevertWhen_NonAdminUpgrades() public {
        address newImplementation = address(new Distribution());

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, distribution.ADMIN_ROLE()
            )
        );
        distribution.upgradeToAndCall(newImplementation, "");
    }
}
