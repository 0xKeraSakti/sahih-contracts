// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { DemoPaymentToken } from "../../src/DemoPaymentToken.sol";

/// @title DemoPaymentTokenTest
/// @author Sahih Contracts
/// @notice Unit tests for the free-mint demo payment token
contract DemoPaymentTokenTest is Test {
    DemoPaymentToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    /// @notice Deploys a fresh demo token before each test
    function setUp() public {
        token = new DemoPaymentToken("Sahih Demo Rupiah", "dIDR");
    }

    /// @notice The token reports its configured name, symbol, and zero decimals
    function test_Metadata() public view {
        assertEq(token.name(), "Sahih Demo Rupiah");
        assertEq(token.symbol(), "dIDR");
        assertEq(token.decimals(), 0);
    }

    /// @notice One token unit equals one Rupiah, so backend figures need no scaling
    function test_OneUnitIsOneRupiah() public {
        vm.prank(alice);
        token.mint(alice, 425_000);

        assertEq(token.balanceOf(alice), 425_000);
    }

    /// @notice Any address can mint to itself without permission
    function test_AnyoneCanMintToThemselves() public {
        vm.prank(alice);
        token.mint(alice, 1000);

        assertEq(token.balanceOf(alice), 1000);
        assertEq(token.totalSupply(), 1000);
    }

    /// @notice Any address can mint to any other address
    function test_AnyoneCanMintToAnotherAddress() public {
        vm.prank(alice);
        token.mint(bob, 2500);

        assertEq(token.balanceOf(bob), 2500);
        assertEq(token.balanceOf(alice), 0);
    }

    /// @notice Minting emits DemoMint
    function test_MintEmitsDemoMint() public {
        vm.expectEmit(true, true, false, false);
        emit DemoPaymentToken.DemoMint(bob, 777);

        vm.prank(alice);
        token.mint(bob, 777);
    }

    /// @notice The faucet mints a fixed amount to the caller
    function test_FaucetMintsFixedAmountToCaller() public {
        vm.prank(alice);
        token.faucet();

        assertEq(token.balanceOf(alice), token.FAUCET_AMOUNT());
    }

    /// @notice The faucet can be called repeatedly, accumulating balance
    function test_FaucetIsRepeatable() public {
        vm.startPrank(alice);
        token.faucet();
        token.faucet();
        vm.stopPrank();

        assertEq(token.balanceOf(alice), token.FAUCET_AMOUNT() * 2);
    }

    /// @notice Transfers are unrestricted, as a payment token must be
    function test_TransfersAreUnrestricted() public {
        vm.prank(alice);
        token.mint(alice, 5000);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 2000));

        assertEq(token.balanceOf(alice), 3000);
        assertEq(token.balanceOf(bob), 2000);
    }

    /// @notice Holders can burn their own balance
    function test_BurnReducesBalanceAndSupply() public {
        vm.startPrank(alice);
        token.mint(alice, 1000);
        token.burn(400);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 600);
        assertEq(token.totalSupply(), 600);
    }

    /// @notice Reverts when minting to the zero address
    function test_RevertWhen_MintingToZeroAddress() public {
        vm.expectRevert(DemoPaymentToken.ZeroAddress.selector);
        token.mint(address(0), 1000);
    }

    /// @notice Reverts when minting zero tokens
    function test_RevertWhen_MintingZeroAmount() public {
        vm.expectRevert(DemoPaymentToken.ZeroAmount.selector);
        token.mint(alice, 0);
    }
}
