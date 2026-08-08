// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Distribution } from "../../src/Distribution.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

/// @title DistributionTest
/// @author Sahih Contracts
/// @notice Unit tests for the Distribution contract
contract DistributionTest is Test, DeployHelpers {
    Distribution internal distribution;
    MockToken internal paymentToken;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal outsider = makeAddr("outsider");
    address internal issuerContract = makeAddr("issuerContract");
    address internal investorA = makeAddr("investorA");
    address internal investorB = makeAddr("investorB");

    /// @notice Deploys a fresh Distribution and funds it with payment tokens before each test
    function setUp() public {
        (distribution, paymentToken) = deployDistribution(admin, operator);
        paymentToken.mint(address(distribution), PAYMENT_TOKEN_FUNDING);
    }

    /// @notice Recording a distribution transfers the correct amounts to each holder
    function test_RecordDistributionTransfersToHolders() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 127_500, investorB, 297_500);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 425_000, CALCULATION_REF_HASH);

        assertEq(paymentToken.balanceOf(investorA), 127_500);
        assertEq(paymentToken.balanceOf(investorB), 297_500);
        assertEq(paymentToken.balanceOf(address(distribution)), PAYMENT_TOKEN_FUNDING - 425_000);
    }

    /// @notice Recording a distribution persists a retrievable distribution record
    function test_RecordDistributionStoresRecord() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, investorB, 200);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 300, CALCULATION_REF_HASH);

        IDistribution.DistributionRecord memory record = distribution.getDistributionRecord(issuerContract, PERIOD_W32);

        assertEq(record.period, PERIOD_W32);
        assertEq(record.totalAmount, 300);
        assertEq(record.distributedAt, block.timestamp);
        assertEq(record.calculationRefHash, CALCULATION_REF_HASH);
        assertTrue(record.recorded);
    }

    /// @notice Recording a distribution emits the Distributed event with the expected data
    function test_RecordDistributionEmitsDistributed() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 500);

        vm.expectEmit(true, true, true, true, address(distribution));
        emit IDistribution.Distributed(
            issuerContract, keccak256(bytes(PERIOD_W32)), PERIOD_W32, 500, 0, block.timestamp
        );

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 500, CALCULATION_REF_HASH);
    }

    /// @notice A distribution with an empty holder list and zero total amount is allowed
    function test_RecordDistributionAllowsZeroTotal() public {
        IDistribution.HolderAmount[] memory holders = new IDistribution.HolderAmount[](0);

        vm.prank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 0, CALCULATION_REF_HASH);

        IDistribution.DistributionRecord memory record = distribution.getDistributionRecord(issuerContract, PERIOD_W32);

        assertTrue(record.recorded);
        assertEq(record.totalAmount, 0);
    }

    /// @notice Reverts when the declared total amount does not match the sum of holder amounts
    function test_RevertWhen_TotalDoesNotMatchBreakdown() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, investorB, 200);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Distribution.DistributionTotalMismatch.selector, 500, 300));
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 500, CALCULATION_REF_HASH);
    }

    /// @notice Reverts when attempting to record a batch of a period that was already recorded
    function test_RevertWhen_BatchAlreadyRecorded() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(Distribution.BatchAlreadyRecorded.selector, issuerContract, PERIOD_W32, 0)
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();
    }

    /// @notice Batches of the same period accumulate into one record and pay every holder exactly once
    function test_RecordDistributionBatchAccumulatesAcrossBatches() public {
        vm.startPrank(operator);
        distribution.recordDistributionBatch(
            issuerContract, PERIOD_W32, singleHolderAmount(investorA, 100), 100, CALCULATION_REF_HASH, 0
        );
        distribution.recordDistributionBatch(
            issuerContract, PERIOD_W32, singleHolderAmount(investorB, 250), 250, CALCULATION_REF_HASH, 1
        );
        vm.stopPrank();

        IDistribution.DistributionRecord memory record = distribution.getDistributionRecord(issuerContract, PERIOD_W32);

        assertEq(record.totalAmount, 350);
        assertEq(paymentToken.balanceOf(investorA), 100);
        assertEq(paymentToken.balanceOf(investorB), 250);
        assertEq(distribution.totalDistributedByIssuer(issuerContract), 350);
        // The period is listed once, no matter how many batches contributed to it
        assertEq(distribution.getRecordedPeriodCount(issuerContract), 1);
    }

    /// @notice Re-sending an already-recorded batch reverts instead of paying its holders twice
    function test_RevertWhen_ReplayingRecordedBatch() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistributionBatch(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH, 1);

        vm.expectRevert(
            abi.encodeWithSelector(Distribution.BatchAlreadyRecorded.selector, issuerContract, PERIOD_W32, 1)
        );
        distribution.recordDistributionBatch(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH, 1);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(investorA), 100);
    }

    /// @notice Reverts when a later batch cites a different off-chain calculation than the first
    function test_RevertWhen_BatchCitesDifferentCalculationRef() public {
        bytes32 otherHash = keccak256("other-calculation");
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistributionBatch(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH, 0);

        vm.expectRevert(
            abi.encodeWithSelector(Distribution.CalculationRefMismatch.selector, CALCULATION_REF_HASH, otherHash)
        );
        distribution.recordDistributionBatch(issuerContract, PERIOD_W32, holders, 100, otherHash, 1);
        vm.stopPrank();
    }

    /// @notice Recorded batches are individually queryable
    function test_IsBatchRecorded() public {
        vm.prank(operator);
        distribution.recordDistributionBatch(
            issuerContract, PERIOD_W32, singleHolderAmount(investorA, 100), 100, CALCULATION_REF_HASH, 2
        );

        assertTrue(distribution.isBatchRecorded(issuerContract, PERIOD_W32, 2));
        assertFalse(distribution.isBatchRecorded(issuerContract, PERIOD_W32, 0));
    }

    /// @notice An admin can rescue tokens stranded in the contract
    function test_AdminRescuesTokens() public {
        address treasury = makeAddr("treasury");

        vm.prank(admin);
        distribution.rescueTokens(address(paymentToken), treasury, 1000);

        assertEq(paymentToken.balanceOf(treasury), 1000);
        assertEq(paymentToken.balanceOf(address(distribution)), PAYMENT_TOKEN_FUNDING - 1000);
    }

    /// @notice Reverts when a non-admin attempts to rescue tokens
    function test_RevertWhen_NonAdminRescuesTokens() public {
        bytes32 adminRole = distribution.ADMIN_ROLE();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, adminRole)
        );
        distribution.rescueTokens(address(paymentToken), operator, 1000);
    }

    /// @notice Investor distributions can be read one page at a time
    function test_GetInvestorDistributionsPaged() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W31, holders, 100, CALCULATION_REF_HASH);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
        distribution.recordDistribution(issuerContract, PERIOD_W33, holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();

        assertEq(distribution.getInvestorDistributionCount(investorA), 3);

        IDistribution.InvestorDistribution[] memory page = distribution.getInvestorDistributionsPaged(investorA, 1, 2);

        assertEq(page.length, 2);
        assertEq(page[0].period, PERIOD_W32);
        assertEq(page[1].period, PERIOD_W33);

        // An offset past the end returns empty rather than reverting
        assertEq(distribution.getInvestorDistributionsPaged(investorA, 99, 2).length, 0);
    }

    /// @notice Recorded periods can be read one page at a time
    function test_GetRecordedPeriodsPaged() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W31, holders, 100, CALCULATION_REF_HASH);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();

        assertEq(distribution.getRecordedPeriodCount(issuerContract), 2);

        string[] memory page = distribution.getRecordedPeriodsPaged(issuerContract, 0, 1);
        assertEq(page.length, 1);
        assertEq(page[0], PERIOD_W31);
    }

    /// @notice Reverts when a paginated query is given a zero limit
    function test_RevertWhen_PagedLimitIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Distribution.InvalidPagination.selector, 0, 0));
        distribution.getInvestorDistributionsPaged(investorA, 0, 0);
    }

    /// @notice Reverts when the contract's token balance is insufficient to cover the distribution
    function test_RevertWhen_ContractBalanceInsufficient() public {
        uint256 amount = PAYMENT_TOKEN_FUNDING + 1;
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, amount);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(Distribution.InsufficientBalance.selector, amount, PAYMENT_TOKEN_FUNDING)
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, amount, CALCULATION_REF_HASH);
    }

    /// @notice Reverts when a non-operator attempts to record a distribution
    function test_RevertWhen_NonOperatorRecordsDistribution() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);
        bytes32 operatorRole = distribution.OPERATOR_ROLE();

        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, operatorRole)
        );
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
    }

    /// @notice Reverts when the number of holders exceeds the maximum allowed per distribution
    function test_RevertWhen_HolderCountExceedsMaximum() public {
        uint256 maxHolders = distribution.MAX_HOLDERS_PER_DISTRIBUTION();
        uint256 count = maxHolders + 1;
        IDistribution.HolderAmount[] memory holders = new IDistribution.HolderAmount[](count);
        for (uint256 i = 0; i < count; ++i) {
            // casting to 'uint160' is safe because i + 1 <= MAX_HOLDERS_PER_DISTRIBUTION + 1
            // forge-lint: disable-next-line(unsafe-typecast)
            holders[i] = IDistribution.HolderAmount({ holderAddress: address(uint160(i + 1)), amount: 1 });
        }

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Distribution.TooManyHolders.selector, count, maxHolders));
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, count, CALCULATION_REF_HASH);
    }

    /// @notice Reverts when a holder entry has the zero address
    function test_RevertWhen_HolderAddressIsZero() public {
        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 100, address(0), 200);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Distribution.InvalidHolder.selector, 1));
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 300, CALCULATION_REF_HASH);
    }

    /// @notice Reverts when the period string is empty
    function test_RevertWhen_PeriodIsEmpty() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.prank(operator);
        vm.expectRevert(Distribution.EmptyPeriod.selector);
        distribution.recordDistribution(issuerContract, "", holders, 100, CALCULATION_REF_HASH);
    }

    /// @notice Reverts when a period identifier does not match the width of the issuer's existing periods
    function test_RevertWhen_PeriodLengthDiffersFromFirstRecorded() public {
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);

        // "2026-W5" would sort after "2026-W32" under the lexicographic comparison used for range queries
        vm.expectRevert(abi.encodeWithSelector(Distribution.PeriodLengthMismatch.selector, 8, 7));
        distribution.recordDistribution(issuerContract, "2026-W5", holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();
    }

    /// @notice Period width is tracked per issuer, so a different issuer may use a different format
    function test_PeriodLengthIsTrackedPerIssuer() public {
        address otherIssuer = makeAddr("otherIssuer");
        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 100);

        vm.startPrank(operator);
        distribution.recordDistribution(issuerContract, PERIOD_W32, holders, 100, CALCULATION_REF_HASH);
        distribution.recordDistribution(otherIssuer, "2026-M07", holders, 100, CALCULATION_REF_HASH);
        vm.stopPrank();

        assertTrue(distribution.getDistributionRecord(otherIssuer, "2026-M07").recorded);
    }

    /// @notice Distribution history is correctly filtered by the given period range
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

    /// @notice An investor's distributions across multiple periods are all returned
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

    /// @notice An admin can update the payment token used for distributions
    function test_AdminUpdatesPaymentToken() public {
        MockToken newToken = new MockToken("Mock Rupiah 2", "MIDR2");

        vm.prank(admin);
        distribution.setPaymentToken(address(newToken));

        assertEq(address(distribution.paymentToken()), address(newToken));
    }

    /// @notice Reverts when a non-admin attempts to upgrade the contract
    function test_RevertWhen_NonAdminUpgrades() public {
        address newImplementation = address(new Distribution());
        bytes32 adminRole = distribution.ADMIN_ROLE();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, adminRole)
        );
        distribution.upgradeToAndCall(newImplementation, "");
    }
}
