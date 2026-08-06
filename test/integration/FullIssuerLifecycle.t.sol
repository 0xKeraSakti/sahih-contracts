// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Factory } from "../../src/Factory.sol";
import { IssuerToken } from "../../src/IssuerToken.sol";
import { Distribution } from "../../src/Distribution.sol";
import { Attester } from "../../src/Attester.sol";
import { IAttester } from "../../src/interfaces/IAttester.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { MockEAS } from "../mocks/MockEAS.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract FullIssuerLifecycleTest is Test, DeployHelpers {
    Factory internal factory;
    Distribution internal distribution;
    Attester internal attester;
    MockEAS internal eas;
    MockToken internal paymentToken;

    bytes32 internal verificationSchema;
    bytes32 internal scoreSchema;
    bytes32 internal distributionSchema;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal investorA = makeAddr("investorA");
    address internal investorB = makeAddr("investorB");

    function setUp() public {
        (factory,) = deployFactory(admin, operator);
        (distribution, paymentToken) = deployDistribution(admin, operator);
        (attester, eas, verificationSchema, scoreSchema, distributionSchema) = deployAttester(admin, operator);

        paymentToken.mint(address(distribution), PAYMENT_TOKEN_FUNDING);
        vm.warp(1_754_179_200);
    }

    function test_LifecycleFromVerificationToDistribution() public {
        bytes32 verificationW31 = _attestVerification(PERIOD_W31, AVG_REVENUE);
        bytes32 scoreW31 = _attestScore(PERIOD_W31, RISK_SCORE);

        assertTrue(verificationW31 != bytes32(0));
        assertTrue(scoreW31 != bytes32(0));

        vm.prank(operator);
        (address contractAddress, uint256 deployedAt) = factory.createIssuerToken(defaultFactoryParams());
        IssuerToken token = IssuerToken(contractAddress);

        assertEq(deployedAt, block.timestamp);
        assertEq(factory.issuerContracts(ISSUER_ID), contractAddress);

        vm.prank(investorA);
        token.purchaseTokens(investorA, 300, "qris");

        vm.prank(investorB);
        token.purchaseTokens(investorB, 700, "qris");

        assertEq(token.totalSupply(), 1_000);
        assertEq(token.remainingSupply(), MAX_SUPPLY - 1_000);

        vm.warp(block.timestamp + 7 days);

        bytes32 verificationW32 = _attestVerification(PERIOD_W32, AVG_REVENUE + 500_000);
        bytes32 scoreW32 = _attestScore(PERIOD_W32, RISK_SCORE + 4);

        assertTrue(verificationW32 != verificationW31);
        assertTrue(scoreW32 != scoreW31);

        IDistribution.HolderAmount[] memory holders = holderAmounts(investorA, 127_500, investorB, 297_500);

        vm.prank(operator);
        distribution.recordDistribution(contractAddress, PERIOD_W32, holders, 425_000, CALCULATION_REF_HASH);

        vm.prank(operator);
        bytes32 distributionUID = attester.attestDistribution(
            IAttester.DistributionPayload({
                issuerId: ISSUER_ID,
                period: PERIOD_W32,
                totalAmount: 425_000,
                calculationRefHash: CALCULATION_REF_HASH,
                timestamp: block.timestamp
            })
        );

        assertEq(paymentToken.balanceOf(investorA), 127_500);
        assertEq(paymentToken.balanceOf(investorB), 297_500);
        assertEq(eas.nonce(), 5);

        (IAttester.VerificationPayload memory storedW31,,) = attester.getVerificationAttestation(verificationW31);
        assertEq(storedW31.period, PERIOD_W31);
        assertEq(storedW31.avgRevenue, AVG_REVENUE);

        (IAttester.DistributionPayload memory storedDistribution,,) =
            attester.getDistributionAttestation(distributionUID);
        assertEq(storedDistribution.totalAmount, 425_000);
        assertEq(storedDistribution.calculationRefHash, CALCULATION_REF_HASH);

        IDistribution.PeriodSummary[] memory history =
            distribution.getDistributionHistory(contractAddress, PERIOD_W31, PERIOD_W33);
        assertEq(history.length, 1);
        assertEq(history[0].period, PERIOD_W32);
    }

    function test_LowRevenuePeriodStillLeavesOnChainTrace() public {
        vm.prank(operator);
        (address contractAddress,) = factory.createIssuerToken(defaultFactoryParams());

        vm.prank(investorA);
        IssuerToken(contractAddress).purchaseTokens(investorA, 100, "qris");

        IDistribution.HolderAmount[] memory holders = singleHolderAmount(investorA, 0);

        vm.prank(operator);
        distribution.recordDistribution(contractAddress, PERIOD_W32, holders, 0, CALCULATION_REF_HASH);

        IDistribution.DistributionRecord memory record =
            distribution.getDistributionRecord(contractAddress, PERIOD_W32);

        assertTrue(record.recorded);
        assertEq(record.totalAmount, 0);
        assertEq(paymentToken.balanceOf(investorA), 0);
    }

    function _attestVerification(string memory period, uint256 avgRevenue) private returns (bytes32) {
        vm.prank(operator);
        return attester.attestVerification(
            IAttester.VerificationPayload({
                issuerId: ISSUER_ID,
                period: period,
                avgRevenue: avgRevenue,
                volatilityIndex: VOLATILITY_INDEX,
                dataRefHash: DATA_REF_HASH,
                timestamp: block.timestamp
            })
        );
    }

    function _attestScore(string memory period, uint256 score) private returns (bytes32) {
        vm.prank(operator);
        return attester.attestScore(
            IAttester.ScorePayload({
                issuerId: ISSUER_ID,
                score: score,
                scoringMethodVersion: SCORING_METHOD_VERSION,
                period: period,
                timestamp: block.timestamp
            })
        );
    }
}
