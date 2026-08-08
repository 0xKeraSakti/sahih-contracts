// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DemoPaymentToken
/// @author Sahih Contracts
/// @notice Unrestricted-mint ERC20 standing in for an IDR stablecoin on testnets
///
/// @dev DEMO AND TESTNET ONLY — ANYONE CAN MINT AN UNLIMITED AMOUNT TO ANY ADDRESS.
///      This token has no access control by design, so a hackathon demo can fund the
///      Distribution contract and top up investors without a faucet service. It holds no
///      value and must never be used on a network where the payouts represent real money.
///      For production, point `PAYMENT_TOKEN_ADDRESS` at a real IDR stablecoin instead.
///
///      Decimals are 0: one token unit is one Rupiah. That makes the amounts passed to
///      `Distribution.recordDistribution` identical to the Rupiah figures the backend
///      calculates — `425000` on-chain is Rp425,000 — removing the scaling step that
///      would otherwise be an easy place to be wrong by a factor of 100 or 1e18.
///
///      It satisfies the constraint `Distribution` relies on: a plain, non-rebasing token
///      with no transfer fee, so `safeTransfer` delivers exactly the recorded amount.
contract DemoPaymentToken is ERC20 {
    /// @notice Amount minted to the caller by a single `faucet()` call
    uint256 public constant FAUCET_AMOUNT = 10_000_000;

    /// @notice Emitted when tokens are minted
    /// @param to Address that received the minted tokens
    /// @param amount Amount of tokens minted
    event DemoMint(address indexed to, uint256 indexed amount);

    error ZeroAddress();
    error ZeroAmount();

    /// @notice Deploys the demo token with the given name and symbol
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) { }

    /// @notice Mints tokens to any address, callable by anyone
    /// @param to Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    function mint(
        address to,
        uint256 amount
    ) external {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        _mint(to, amount);

        emit DemoMint(to, amount);
    }

    /// @notice Mints a fixed amount to the caller
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);

        emit DemoMint(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Burns tokens from the caller
    /// @param amount Amount of tokens to burn
    function burn(
        uint256 amount
    ) external {
        _burn(msg.sender, amount);
    }

    /// @notice Returns the number of decimals, fixed at zero so one unit equals one Rupiah
    /// @return Always zero
    function decimals() public pure override returns (uint8) {
        return 0;
    }
}
