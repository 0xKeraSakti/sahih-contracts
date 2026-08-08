// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { SahihAttestationRegistry } from "../../src/SahihAttestationRegistry.sol";
import { SahihSchemaRegistry } from "../../src/SahihSchemaRegistry.sol";
import { ISchemaRegistry } from "../../src/interfaces/ISchemaRegistry.sol";
import { AttestationRequest, AttestationRequestData, EASAttestation } from "../../src/interfaces/IEAS.sol";
import { SahihSchemas } from "../../src/libraries/SahihSchemas.sol";

/// @title SahihAttestationRegistryTest
/// @author Sahih Contracts
/// @notice Unit tests for the standalone attestation registry
contract SahihAttestationRegistryTest is Test {
    SahihSchemaRegistry internal schemaRegistry;
    SahihAttestationRegistry internal registry;
    bytes32 internal verificationSchema;

    address internal attester = makeAddr("attester");

    /// @notice Deploys a schema registry with the verification schema and a fresh attestation registry
    function setUp() public {
        schemaRegistry = new SahihSchemaRegistry();
        verificationSchema = schemaRegistry.register(SahihSchemas.VERIFICATION, address(0), false);
        registry = new SahihAttestationRegistry(schemaRegistry);
        vm.warp(1_754_179_200);
    }

    /// @notice An attestation is stored with the submitted data and the caller as attester
    function test_AttestStoresAttestation() public {
        bytes memory data = abi.encode("UMKM-001", "2026-W31");

        vm.prank(attester);
        bytes32 uid = registry.attest(_request(verificationSchema, data));

        EASAttestation memory attestation = registry.getAttestation(uid);

        assertEq(attestation.uid, uid);
        assertEq(attestation.schema, verificationSchema);
        assertEq(attestation.attester, attester);
        assertEq(attestation.data, data);
        assertEq(attestation.time, uint64(block.timestamp));
        assertEq(attestation.revocationTime, 0);
        assertFalse(attestation.revocable);
    }

    /// @notice Each recorded attestation increments the running count
    function test_AttestIncrementsCount() public {
        assertEq(registry.attestationCount(), 0);

        vm.startPrank(attester);
        registry.attest(_request(verificationSchema, abi.encode("a")));
        registry.attest(_request(verificationSchema, abi.encode("b")));
        vm.stopPrank();

        assertEq(registry.attestationCount(), 2);
    }

    /// @notice Attesting emits Attested with the UID, schema, and attester
    function test_AttestEmitsAttested() public {
        vm.recordLogs();

        vm.prank(attester);
        bytes32 uid = registry.attest(_request(verificationSchema, abi.encode("x")));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Attested(bytes32,bytes32,address)"));
        assertEq(logs[0].topics[1], uid);
        assertEq(logs[0].topics[2], verificationSchema);
        assertEq(address(uint160(uint256(logs[0].topics[3]))), attester);
    }

    /// @notice Two byte-identical attestations in the same block receive distinct UIDs
    function test_IdenticalAttestationsInSameBlockGetDistinctUIDs() public {
        AttestationRequest memory request = _request(verificationSchema, abi.encode("identical"));

        vm.startPrank(attester);
        bytes32 first = registry.attest(request);
        bytes32 second = registry.attest(request);
        vm.stopPrank();

        assertTrue(first != second);
        assertEq(registry.getAttestation(first).uid, first);
        assertEq(registry.getAttestation(second).uid, second);
        assertEq(registry.attestationCount(), 2);
    }

    /// @notice A recorded attestation is never mutated by a later attestation
    function test_AttestationsAreAppendOnly() public {
        vm.startPrank(attester);
        bytes32 first = registry.attest(_request(verificationSchema, abi.encode("first")));
        registry.attest(_request(verificationSchema, abi.encode("second")));
        vm.stopPrank();

        assertEq(registry.getAttestation(first).data, abi.encode("first"));
    }

    /// @notice An unknown UID resolves to a zero-valued attestation rather than reverting
    function test_UnknownUIDReturnsEmptyAttestation() public view {
        EASAttestation memory attestation = registry.getAttestation(keccak256("never-attested"));

        assertEq(attestation.uid, bytes32(0));
        assertEq(attestation.attester, address(0));
    }

    /// @notice Reverts when attesting against a schema that was never registered
    function test_RevertWhen_SchemaNotRegistered() public {
        bytes32 unknown = keccak256("unregistered-schema");

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSelector(SahihAttestationRegistry.SchemaNotRegistered.selector, unknown));
        registry.attest(_request(unknown, abi.encode("x")));
    }

    /// @notice Reverts when requesting a revocable attestation, which this registry does not support
    function test_RevertWhen_AttestationIsRevocable() public {
        AttestationRequest memory request = _request(verificationSchema, abi.encode("x"));
        request.data.revocable = true;

        vm.prank(attester);
        vm.expectRevert(SahihAttestationRegistry.RevocationNotSupported.selector);
        registry.attest(request);
    }

    /// @notice Reverts when ETH is sent with an attestation
    function test_RevertWhen_EthSentWithAttestation() public {
        vm.deal(attester, 1 ether);

        vm.prank(attester);
        vm.expectRevert(SahihAttestationRegistry.ValueNotAccepted.selector);
        registry.attest{ value: 1 wei }(_request(verificationSchema, abi.encode("x")));
    }

    /// @notice Reverts when the request declares a non-zero value
    function test_RevertWhen_RequestDeclaresValue() public {
        AttestationRequest memory request = _request(verificationSchema, abi.encode("x"));
        request.data.value = 1;

        vm.prank(attester);
        vm.expectRevert(SahihAttestationRegistry.ValueNotAccepted.selector);
        registry.attest(request);
    }

    /// @notice Reverts when deploying against a zero-address schema registry
    function test_RevertWhen_SchemaRegistryIsZeroAddress() public {
        vm.expectRevert(SahihAttestationRegistry.ZeroAddress.selector);
        new SahihAttestationRegistry(ISchemaRegistry(address(0)));
    }

    /// @notice Builds an attestation request for the given schema and payload
    /// @param schema Schema UID to attest against
    /// @param data ABI-encoded attestation payload
    /// @return The attestation request
    function _request(
        bytes32 schema,
        bytes memory data
    ) private pure returns (AttestationRequest memory) {
        return AttestationRequest({
            schema: schema,
            data: AttestationRequestData({
                recipient: address(0), expirationTime: 0, revocable: false, refUID: bytes32(0), data: data, value: 0
            })
        });
    }
}
