// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IIssuerToken
/// @author Sahih Contracts
/// @notice Interface for the ERC20 token representing an issuer's tradable profit-sharing units
interface IIssuerToken {
    /// @notice Parameters used to initialize a new issuer token
    struct InitParams {
        string issuerId;
        string tokenName;
        string tokenSymbol;
        uint256 maxSupply;
        uint256 pricePerUnit;
        uint256 profitSharingRatio;
        string distributionPeriod;
        bool transferRestricted;
        address admin;
        address operator;
    }

    /// @notice Current terms of an issuer token
    struct IssuerTerms {
        uint256 profitSharingRatio;
        uint256 totalSupply;
        uint256 pricePerUnit;
        string distributionPeriod;
        bool transferRestricted;
    }

    /// @notice Emitted when an investor purchases tokens
    /// @param investor Address that received the minted tokens
    /// @param amount Amount of tokens minted
    /// @param paymentSource Reference to the off-chain payment source
    /// @param timestamp Timestamp the purchase was recorded
    event Purchase(address indexed investor, uint256 indexed amount, string paymentSource, uint256 timestamp);
    /// @notice Emitted when the transfer whitelist is updated
    /// @param account Address whose whitelist status changed
    /// @param allowed Whether the account is now whitelisted
    event TransferWhitelistUpdated(address indexed account, bool indexed allowed);
    /// @notice Emitted when the transfer restriction state is updated
    /// @param restricted New transfer restriction state
    event TransferRestrictionUpdated(bool indexed restricted);

    /// @notice Initializes the token, setting terms and granting roles
    /// @param params Issuer terms, token metadata, and role addresses
    function initialize(
        InitParams calldata params
    ) external;

    /// @notice Mints tokens to an investor in exchange for an off-chain payment
    /// @param investorAddress Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    /// @param paymentSource Reference to the off-chain payment source
    function purchaseTokens(
        address investorAddress,
        uint256 amount,
        string calldata paymentSource
    ) external;

    /// @notice Updates whether an account may receive tokens while transfers are restricted
    /// @param account Address to update
    /// @param allowed Whether the account is whitelisted
    function setTransferWhitelist(
        address account,
        bool allowed
    ) external;

    /// @notice Updates whether transfers are restricted to whitelisted recipients
    /// @param restricted New transfer restriction state
    function setTransferRestricted(
        bool restricted
    ) external;

    /// @notice Returns the current issuer terms
    /// @return Current profit sharing ratio, supply, price, distribution period, and transfer restriction
    function getIssuerTerms() external view returns (IssuerTerms memory);

    /// @notice Returns the amount of supply remaining to be minted
    /// @return Remaining mintable supply
    function remainingSupply() external view returns (uint256);
}
