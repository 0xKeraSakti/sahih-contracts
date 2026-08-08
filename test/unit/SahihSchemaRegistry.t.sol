// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { SahihSchemaRegistry } from "../../src/SahihSchemaRegistry.sol";
import { ISchemaRegistry, SchemaRecord } from "../../src/interfaces/ISchemaRegistry.sol";
import { SahihSchemas } from "../../src/libraries/SahihSchemas.sol";

/// @title SahihSchemaRegistryTest
/// @author Sahih Contracts
/// @notice Unit tests for the standalone schema registry
contract SahihSchemaRegistryTest is Test {
    SahihSchemaRegistry internal registry;

    address internal registerer = makeAddr("registerer");

    /// @notice Deploys a fresh schema registry before each test
    function setUp() public {
        registry = new SahihSchemaRegistry();
    }

    /// @notice Registering a schema stores a record retrievable by the returned UID
    function test_RegisterStoresRetrievableRecord() public {
        vm.prank(registerer);
        bytes32 uid = registry.register(SahihSchemas.VERIFICATION, address(0), false);

        SchemaRecord memory record = registry.getSchema(uid);

        assertEq(record.uid, uid);
        assertEq(record.resolver, address(0));
        assertFalse(record.revocable);
        assertEq(record.schema, SahihSchemas.VERIFICATION);
        assertTrue(registry.isRegistered(uid));
    }

    /// @notice The returned UID matches the EAS derivation, keccak256(schema, resolver, revocable)
    function test_UIDMatchesEASDerivation() public {
        bytes32 expected = keccak256(abi.encodePacked(SahihSchemas.SCORE, address(0), false));

        bytes32 uid = registry.register(SahihSchemas.SCORE, address(0), false);

        assertEq(uid, expected);
        assertEq(registry.computeUID(SahihSchemas.SCORE, address(0), false), expected);
    }

    /// @notice Registering emits Registered with the UID, caller, and schema definition
    function test_RegisterEmitsRegistered() public {
        bytes32 expected = registry.computeUID(SahihSchemas.DISTRIBUTION, address(0), false);

        vm.expectEmit(true, true, false, true);
        emit ISchemaRegistry.Registered(expected, registerer, SahihSchemas.DISTRIBUTION);

        vm.prank(registerer);
        registry.register(SahihSchemas.DISTRIBUTION, address(0), false);
    }

    /// @notice The three platform schemas register to three distinct UIDs
    function test_PlatformSchemasRegisterToDistinctUIDs() public {
        bytes32 verification = registry.register(SahihSchemas.VERIFICATION, address(0), false);
        bytes32 score = registry.register(SahihSchemas.SCORE, address(0), false);
        bytes32 distribution = registry.register(SahihSchemas.DISTRIBUTION, address(0), false);

        assertTrue(verification != score);
        assertTrue(score != distribution);
        assertTrue(verification != distribution);
    }

    /// @notice Changing the resolver or revocable flag yields a different UID for the same definition
    function test_ResolverAndRevocableAffectUID() public view {
        bytes32 base = registry.computeUID(SahihSchemas.VERIFICATION, address(0), false);
        bytes32 withResolver = registry.computeUID(SahihSchemas.VERIFICATION, address(1), false);
        bytes32 withRevocable = registry.computeUID(SahihSchemas.VERIFICATION, address(0), true);

        assertTrue(base != withResolver);
        assertTrue(base != withRevocable);
    }

    /// @notice An unregistered UID resolves to a zero-valued record
    function test_UnknownUIDReturnsEmptyRecord() public view {
        SchemaRecord memory record = registry.getSchema(keccak256("never-registered"));

        assertEq(record.uid, bytes32(0));
        assertEq(bytes(record.schema).length, 0);
        assertFalse(registry.isRegistered(keccak256("never-registered")));
    }

    /// @notice Reverts when registering an empty schema definition
    function test_RevertWhen_SchemaIsEmpty() public {
        vm.expectRevert(SahihSchemaRegistry.EmptySchema.selector);
        registry.register("", address(0), false);
    }

    /// @notice Reverts when registering a schema that already exists
    function test_RevertWhen_SchemaAlreadyRegistered() public {
        bytes32 uid = registry.register(SahihSchemas.VERIFICATION, address(0), false);

        vm.expectRevert(abi.encodeWithSelector(SahihSchemaRegistry.SchemaAlreadyRegistered.selector, uid));
        registry.register(SahihSchemas.VERIFICATION, address(0), false);
    }

    /// @notice A registered schema is never mutated by a later registration of a different schema
    function test_RegistrationIsAppendOnly() public {
        bytes32 verification = registry.register(SahihSchemas.VERIFICATION, address(0), false);
        registry.register(SahihSchemas.SCORE, address(0), false);

        assertEq(registry.getSchema(verification).schema, SahihSchemas.VERIFICATION);
    }
}
