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

    uint256[50] private __gap;

    error ZeroAddress();
    error ZeroAmount();
    error EmptyIssuerId();
    error EmptyDistributionPeriod();
    error InvalidMaxSupply();
    error InvalidPricePerUnit();
    error InvalidProfitSharingRatio(uint256 ratio);
    error UnauthorizedPurchaser(address caller, address investorAddress);
    error SupplyExceeded(uint256 requested, uint256 remaining);
    error TransferRestricted();

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
        if (params.distributionPeriod.isEmpty()) {
            revert EmptyDistributionPeriod();
        }
        if (params.admin == address(0) || params.operator == address(0)) {
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
        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(ADMIN_ROLE, params.admin);
        _grantRole(OPERATOR_ROLE, params.operator);

        issuerId = params.issuerId;
        maxSupply = params.maxSupply;
        pricePerUnit = params.pricePerUnit;
        profitSharingRatio = params.profitSharingRatio;
        distributionPeriod = params.distributionPeriod;
        transferRestricted = params.transferRestricted;
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

    /// @notice Returns the current issuer terms
    /// @return Current profit sharing ratio, supply, price, distribution period, and transfer restriction
    function getIssuerTerms() external view returns (IssuerTerms memory) {
        return IssuerTerms({
            profitSharingRatio: profitSharingRatio,
            totalSupply: maxSupply,
            pricePerUnit: pricePerUnit,
            distributionPeriod: distributionPeriod,
            transferRestricted: transferRestricted
        });
    }

    /// @notice Returns the amount of supply remaining to be minted
    /// @return Remaining mintable supply
    function remainingSupply() external view returns (uint256) {
        return maxSupply - totalSupply();
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
