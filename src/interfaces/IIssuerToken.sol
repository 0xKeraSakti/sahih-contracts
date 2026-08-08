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
        address factory;
        address issuerWallet;
    }

    /// @notice Current terms of an issuer token
    struct IssuerTerms {
        uint256 profitSharingRatio;
        uint256 maxSupply;
        uint256 circulatingSupply;
        uint256 pricePerUnit;
        string distributionPeriod;
        bool transferRestricted;
        bool active;
    }

    /// @notice Emitted when an investor purchases tokens
    /// @param investor Address that received the minted tokens
    /// @param amount Amount of tokens minted
    /// @param paymentSource Reference to the off-chain payment source
    /// @param timestamp Timestamp the purchase was recorded
    event Purchase(address indexed investor, uint256 amount, string paymentSource, uint256 timestamp);
    /// @notice Emitted when the issuer's active status is updated
    /// @param active New active status
    event ActiveStatusUpdated(bool indexed active);
    /// @notice Emitted when purchases are paused or resumed
    /// @param paused New purchase pause state
    event PurchasePausedUpdated(bool indexed paused);
    /// @notice Emitted when the issuer's payout wallet is updated
    /// @param issuerWallet New issuer wallet address
    event IssuerWalletUpdated(address indexed issuerWallet);
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

    /// @notice Updates whether the issuer is active and may sell new tokens
    /// @param active_ New active status
    function setActive(
        bool active_
    ) external;

    /// @notice Returns whether the issuer is active and may sell new tokens
    /// @return True if the issuer is active
    function active() external view returns (bool);

    /// @notice Pauses or resumes purchases without changing the issuer's active status
    /// @param paused New purchase pause state
    function setPurchasePaused(
        bool paused
    ) external;

    /// @notice Returns whether purchases are currently paused
    /// @return True if purchases are paused
    function purchasePaused() external view returns (bool);

    /// @notice Updates the issuer's own payout wallet address
    /// @param issuerWallet_ New issuer wallet address
    function setIssuerWallet(
        address issuerWallet_
    ) external;

    /// @notice Returns the issuer's own wallet address
    /// @return The issuer's wallet address
    function issuerWallet() external view returns (address);

    /// @notice Reads several holder balances and the circulating supply in a single call
    /// @param accounts Holder addresses to read balances for
    /// @return balances Balance of each account, in the order given
    /// @return circulatingSupply Total supply minted so far, read in the same call
    function balancesAt(
        address[] calldata accounts
    ) external view returns (uint256[] memory balances, uint256 circulatingSupply);

    /// @notice Returns the current issuer terms
    /// @return Current profit sharing ratio, supply, price, distribution period, and transfer restriction
    function getIssuerTerms() external view returns (IssuerTerms memory);

    /// @notice Returns the amount of supply remaining to be minted
    /// @return Remaining mintable supply
    function remainingSupply() external view returns (uint256);

    /// @notice Quotes how many whole units a payment buys at the current unit price
    /// @param paidAmount Amount paid, in the same currency unit as `pricePerUnit`
    /// @return units Whole units the payment covers, rounded down
    /// @return change Remainder of `paidAmount` that does not cover a further whole unit
    function quotePurchase(
        uint256 paidAmount
    ) external view returns (uint256 units, uint256 change);
}
