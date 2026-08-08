// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IIssuerToken } from "./interfaces/IIssuerToken.sol";
import { PeriodLib } from "./libraries/PeriodLib.sol";

/// @title IssuerToken
/// @author Sahih Contracts
/// @notice ERC20 token representing an issuer's tradable profit-sharing units
contract IssuerToken is IIssuerToken, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using PeriodLib for string;

    /// @notice Role allowed to update transfer restrictions and the whitelist
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role allowed to purchase tokens on behalf of an investor
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Role held by the deploying factory, allowed to update the active status
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    /// @notice Maximum allowed profit sharing ratio, in basis points
    uint256 public constant MAX_PROFIT_SHARING_RATIO = 10_000;

    /// @notice Identifier of the issuer this token represents
    string public issuerId;
    /// @notice Share of profit distributed to holders, in basis points
    uint256 public profitSharingRatio;
    /// @notice Price per unit at issuance
    uint256 public pricePerUnit;
    /// @notice Period identifier distributions are paid against
    string public distributionPeriod;
    /// @notice Whether transfers are restricted to whitelisted recipients
    bool public transferRestricted;
    /// @notice Whether an address is allowed to receive tokens when transfers are restricted
    mapping(address => bool) public transferWhitelist;
    /// @notice Maximum total supply that can be minted
    uint256 public maxSupply;
    /// @notice Whether the issuer is active and may sell new tokens
    bool public active;
    /// @notice Whether purchases are temporarily paused, independent of the active status
    bool public purchasePaused;
    /// @notice The issuer's own wallet address, used for off-chain settlement and identification
    address public issuerWallet;

    uint256[48] private __gap;

    error ZeroAddress();
    error ZeroAmount();
    error EmptyIssuerId();
    error EmptyTokenName();
    error EmptyTokenSymbol();
    error EmptyDistributionPeriod();
    error InvalidMaxSupply();
    error InvalidPricePerUnit();
    error InvalidProfitSharingRatio(uint256 ratio);
    error UnauthorizedPurchaser(address caller, address investorAddress);
    error UnauthorizedStatusUpdate(address caller);
    error SupplyExceeded(uint256 requested, uint256 remaining);
    error TransferRestricted();
    error IssuerInactive();
    error PurchasePaused();

    /// @notice Disables initializers on the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token, setting terms and granting roles
    /// @param params Issuer terms, token metadata, and role addresses
    function initialize(
        InitParams calldata params
    ) external initializer {
        if (params.issuerId.isEmpty()) {
            revert EmptyIssuerId();
        }
        if (params.tokenName.isEmpty()) {
            revert EmptyTokenName();
        }
        if (params.tokenSymbol.isEmpty()) {
            revert EmptyTokenSymbol();
        }
        if (params.distributionPeriod.isEmpty()) {
            revert EmptyDistributionPeriod();
        }
        if (params.admin == address(0) || params.operator == address(0) || params.issuerWallet == address(0)) {
            revert ZeroAddress();
        }
        if (params.maxSupply == 0) {
            revert InvalidMaxSupply();
        }
        if (params.pricePerUnit == 0) {
            revert InvalidPricePerUnit();
        }
        if (params.profitSharingRatio == 0 || params.profitSharingRatio > MAX_PROFIT_SHARING_RATIO) {
            revert InvalidProfitSharingRatio(params.profitSharingRatio);
        }

        __ERC20_init(params.tokenName, params.tokenSymbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(FACTORY_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(ADMIN_ROLE, params.admin);
        _grantRole(OPERATOR_ROLE, params.operator);
        // A token deployed standalone (outside the factory) has no factory to grant the role to;
        // the admin path in setActive covers status updates in that case
        if (params.factory != address(0)) {
            _grantRole(FACTORY_ROLE, params.factory);
        }

        issuerId = params.issuerId;
        maxSupply = params.maxSupply;
        pricePerUnit = params.pricePerUnit;
        profitSharingRatio = params.profitSharingRatio;
        distributionPeriod = params.distributionPeriod;
        transferRestricted = params.transferRestricted;
        issuerWallet = params.issuerWallet;
        active = true;
    }

    /// @notice Mints tokens to an investor in exchange for an off-chain payment
    /// @param investorAddress Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    /// @param paymentSource Reference to the off-chain payment source
    function purchaseTokens(
        address investorAddress,
        uint256 amount,
        string calldata paymentSource
    ) external {
        if (!active) {
            revert IssuerInactive();
        }
        if (purchasePaused) {
            revert PurchasePaused();
        }
        if (investorAddress == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != investorAddress && !hasRole(OPERATOR_ROLE, msg.sender)) {
            revert UnauthorizedPurchaser(msg.sender, investorAddress);
        }

        uint256 remaining = maxSupply - totalSupply();
        if (amount > remaining) {
            revert SupplyExceeded(amount, remaining);
        }

        _mint(investorAddress, amount);

        emit Purchase(investorAddress, amount, paymentSource, block.timestamp);
    }

    /// @notice Updates whether an account may receive tokens while transfers are restricted
    /// @param account Address to update
    /// @param allowed Whether the account is whitelisted
    function setTransferWhitelist(
        address account,
        bool allowed
    ) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) {
            revert ZeroAddress();
        }
        transferWhitelist[account] = allowed;

        emit TransferWhitelistUpdated(account, allowed);
    }

    /// @notice Updates whether transfers are restricted to whitelisted recipients
    /// @param restricted New transfer restriction state
    function setTransferRestricted(
        bool restricted
    ) external onlyRole(ADMIN_ROLE) {
        transferRestricted = restricted;

        emit TransferRestrictionUpdated(restricted);
    }

    /// @notice Updates whether the issuer is active and may sell new tokens
    /// @dev Callable by the deploying factory (via `Factory.setIssuerStatus`) or directly by an admin
    /// @param active_ New active status
    function setActive(
        bool active_
    ) external {
        if (!hasRole(FACTORY_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert UnauthorizedStatusUpdate(msg.sender);
        }
        active = active_;

        emit ActiveStatusUpdated(active_);
    }

    /// @notice Pauses or resumes purchases without changing the issuer's active status
    /// @dev Held by the operator so the backend can freeze minting while it snapshots holder balances
    /// for a distribution, without having to deactivate the issuer entirely
    /// @param paused New purchase pause state
    function setPurchasePaused(
        bool paused
    ) external onlyRole(OPERATOR_ROLE) {
        purchasePaused = paused;

        emit PurchasePausedUpdated(paused);
    }

    /// @notice Updates the issuer's own payout wallet address
    /// @param issuerWallet_ New issuer wallet address
    function setIssuerWallet(
        address issuerWallet_
    ) external onlyRole(ADMIN_ROLE) {
        if (issuerWallet_ == address(0)) {
            revert ZeroAddress();
        }
        issuerWallet = issuerWallet_;

        emit IssuerWalletUpdated(issuerWallet_);
    }

    /// @notice Reads several holder balances and the circulating supply in a single call
    /// @dev Every value is read within one call, so the whole set is guaranteed to come from the same
    /// block. This is what makes a distribution snapshot internally consistent without an archive node
    /// @param accounts Holder addresses to read balances for
    /// @return balances Balance of each account, in the order given
    /// @return circulatingSupply Total supply minted so far
    function balancesAt(
        address[] calldata accounts
    ) external view returns (uint256[] memory balances, uint256 circulatingSupply) {
        balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            balances[i] = balanceOf(accounts[i]);
        }
        circulatingSupply = totalSupply();
    }

    /// @notice Returns the current issuer terms
    /// @dev `maxSupply` is the mintable cap; `circulatingSupply` is what has actually been minted so far.
    /// Use `circulatingSupply` when calculating each holder's proportional share of a distribution
    /// @return Current profit sharing ratio, supply figures, price, distribution period, and status flags
    function getIssuerTerms() external view returns (IssuerTerms memory) {
        return IssuerTerms({
            profitSharingRatio: profitSharingRatio,
            maxSupply: maxSupply,
            circulatingSupply: totalSupply(),
            pricePerUnit: pricePerUnit,
            distributionPeriod: distributionPeriod,
            transferRestricted: transferRestricted,
            active: active
        });
    }

    /// @notice Returns the amount of supply remaining to be minted
    /// @return Remaining mintable supply
    function remainingSupply() external view returns (uint256) {
        return maxSupply - totalSupply();
    }

    /// @notice Quotes how many whole units a payment buys at the current unit price
    /// @dev Units are indivisible, so the quote rounds down and reports the shortfall as `change`.
    /// This is a pure quote: it neither reserves supply nor verifies that payment was received
    /// @param paidAmount Amount paid, in the same currency unit as `pricePerUnit`
    /// @return units Whole units the payment covers, rounded down
    /// @return change Remainder of `paidAmount` that does not cover a further whole unit
    function quotePurchase(
        uint256 paidAmount
    ) external view returns (uint256 units, uint256 change) {
        // pricePerUnit is validated non-zero at initialization, so this cannot divide by zero
        units = paidAmount / pricePerUnit;
        change = paidAmount - (units * pricePerUnit);
    }

    /// @notice Returns the number of decimals the token uses
    /// @dev Sukuk units are indivisible, so this overrides the ERC20 default of 18. Balances,
    /// `maxSupply`, and `pricePerUnit` are therefore all expressed in whole units
    /// @return Always zero
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    /// @notice Enforces the transfer whitelist when transfers are restricted
    /// @param from Address tokens are transferred from
    /// @param to Address tokens are transferred to
    /// @param value Amount of tokens transferred
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (transferRestricted && from != address(0) && to != address(0) && !transferWhitelist[to]) {
            revert TransferRestricted();
        }
        super._update(from, to, value);
    }

    // solhint-disable no-empty-blocks
    /// @notice Authorizes a UUPS upgrade; restricted to the admin role
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }
    // solhint-enable no-empty-blocks
}
