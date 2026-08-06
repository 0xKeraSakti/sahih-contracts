// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Attester } from "../../src/Attester.sol";
import { IAttester } from "../../src/interfaces/IAttester.sol";
import { EASAttestation } from "../../src/interfaces/IEAS.sol";
import { MockEAS } from "../mocks/MockEAS.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract AttesterTest is Test, DeployHelpers {
    Attester internal attester;
    MockEAS internal eas;
    bytes32 internal verificationSchema;
    bytes32 internal scoreSchema;
    bytes32 internal distributionSchema;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        (attester, eas, verificationSchema, scoreSchema, distributionSchema) = deployAttester(admin, operator);
    }

    function test_AttestVerificationStoresDecodablePayload() public {
        vm.prank(operator);
        bytes32 uid = attester.attestVerification(_verificationPayload());

        (IAttester.VerificationPayload memory payload, address attesterAddress,) =
            attester.getVerificationAttestation(uid);

        assertEq(payload.issuerId, ISSUER_ID);
        assertEq(payload.period, PERIOD_W31);
        assertEq(payload.avgRevenue, AVG_REVENUE);
        assertEq(payload.volatilityIndex, VOLATILITY_INDEX);
        assertEq(payload.dataRefHash, DATA_REF_HASH);
        assertEq(attesterAddress, address(attester));
    }

    function test_AttestScoreStoresDecodablePayload() public {
        vm.prank(operator);
        bytes32 uid = attester.attestScore(_scorePayload());

        (IAttester.ScorePayload memory payload,,) = attester.getScoreAttestation(uid);

        assertEq(payload.issuerId, ISSUER_ID);
        assertEq(payload.score, RISK_SCORE);
        assertEq(payload.scoringMethodVersion, SCORING_METHOD_VERSION);
        assertEq(payload.period, PERIOD_W31);
    }

    function test_AttestDistributionStoresDecodablePayload() public {
        vm.prank(operator);
        bytes32 uid = attester.attestDistribution(_distributionPayload());

        (IAttester.DistributionPayload memory payload,,) = attester.getDistributionAttestation(uid);

        assertEq(payload.issuerId, ISSUER_ID);
        assertEq(payload.period, PERIOD_W32);
        assertEq(payload.totalAmount, 425_000);
        assertEq(payload.calculationRefHash, CALCULATION_REF_HASH);
    }

    function test_AttestationsAreAppendedNotMutated() public {
        vm.startPrank(operator);
        bytes32 firstUID = attester.attestVerification(_verificationPayload());

        IAttester.VerificationPayload memory second = _verificationPayload();
        second.period = PERIOD_W32;
        second.avgRevenue = AVG_REVENUE + 1_000_000;
        bytes32 secondUID = attester.attestVerification(second);
        vm.stopPrank();

        assertTrue(firstUID != secondUID);

        (IAttester.VerificationPayload memory stored,,) = attester.getVerificationAttestation(firstUID);
        assertEq(stored.period, PERIOD_W31);
        assertEq(stored.avgRevenue, AVG_REVENUE);
    }

    function test_AttestationIsNotRevocable() public {
        vm.prank(operator);
        bytes32 uid = attester.attestVerification(_verificationPayload());

        EASAttestation memory attestation = attester.getAttestation(uid);

        assertFalse(attestation.revocable);
        assertEq(attestation.schema, verificationSchema);
    }

    function test_RevertWhen_NonOperatorAttests() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, attester.OPERATOR_ROLE()
            )
        );
        attester.attestVerification(_verificationPayload());
    }

    function test_RevertWhen_SchemaNotSet() public {
        vm.prank(admin);
        attester.setSchemas(bytes32(0), scoreSchema, distributionSchema);

        vm.prank(operator);
        vm.expectRevert(Attester.SchemaNotSet.selector);
        attester.attestVerification(_verificationPayload());
    }

    function test_RevertWhen_SchemaMismatchOnDecode() public {
        vm.prank(operator);
        bytes32 uid = attester.attestScore(_scorePayload());

        vm.expectRevert(abi.encodeWithSelector(Attester.SchemaMismatch.selector, verificationSchema, scoreSchema));
        attester.getVerificationAttestation(uid);
    }

    function test_RevertWhen_AttestationNotFound() public {
        bytes32 unknown = keccak256("unknown");

        vm.expectRevert(abi.encodeWithSelector(Attester.AttestationNotFound.selector, unknown));
        attester.getAttestation(unknown);
    }

    function test_RevertWhen_NonAdminSetsSchemas() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, attester.ADMIN_ROLE()
            )
        );
        attester.setSchemas(bytes32(0), bytes32(0), bytes32(0));
    }

    function _verificationPayload() private pure returns (IAttester.VerificationPayload memory) {
        return IAttester.VerificationPayload({
            issuerId: ISSUER_ID,
            period: PERIOD_W31,
            avgRevenue: AVG_REVENUE,
            volatilityIndex: VOLATILITY_INDEX,
            dataRefHash: DATA_REF_HASH,
            timestamp: 1_754_211_600
        });
    }

    function _scorePayload() private pure returns (IAttester.ScorePayload memory) {
        return IAttester.ScorePayload({
            issuerId: ISSUER_ID,
            score: RISK_SCORE,
            scoringMethodVersion: SCORING_METHOD_VERSION,
            period: PERIOD_W31,
            timestamp: 1_754_211_900
        });
    }

    function _distributionPayload() private pure returns (IAttester.DistributionPayload memory) {
        return IAttester.DistributionPayload({
            issuerId: ISSUER_ID,
            period: PERIOD_W32,
            totalAmount: 425_000,
            calculationRefHash: CALCULATION_REF_HASH,
            timestamp: 1_754_820_000
        });
    }
}
