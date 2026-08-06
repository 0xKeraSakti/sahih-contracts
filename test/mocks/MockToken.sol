// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockToken
/// @author Sahih Contracts
/// @notice Minimal mintable/burnable ERC20 used as a payment token in tests
contract MockToken is ERC20 {
    /// @notice Deploys the mock token with the given name and symbol
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) { }

    /// @notice Mints tokens to an address
    /// @param to Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }

    /// @notice Burns tokens from an address
    /// @param from Address to burn tokens from
    /// @param amount Amount of tokens to burn
    function burn(
        address from,
        uint256 amount
    ) external {
        _burn(from, amount);
    }
}
