// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IIssuerToken } from "./interfaces/IIssuerToken.sol";
import { PeriodLib } from "./libraries/PeriodLib.sol";

contract IssuerToken is IIssuerToken, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using PeriodLib for string;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MAX_PROFIT_SHARING_RATIO = 10_000;

    string public issuerId;
    uint256 public profitSharingRatio;
    uint256 public pricePerUnit;
    string public distributionPeriod;
    bool public transferRestricted;
    mapping(address => bool) public transferWhitelist;
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

    constructor() {
        _disableInitializers();
    }

    function initialize(InitParams calldata params) external initializer {
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

    function purchaseTokens(address investorAddress, uint256 amount, string calldata paymentSource) external {
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

    function setTransferWhitelist(address account, bool allowed) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) {
            revert ZeroAddress();
        }
        transferWhitelist[account] = allowed;

        emit TransferWhitelistUpdated(account, allowed);
    }

    function setTransferRestricted(bool restricted) external onlyRole(ADMIN_ROLE) {
        transferRestricted = restricted;

        emit TransferRestrictionUpdated(restricted);
    }

    function getIssuerTerms() external view returns (IssuerTerms memory) {
        return IssuerTerms({
            profitSharingRatio: profitSharingRatio,
            totalSupply: maxSupply,
            pricePerUnit: pricePerUnit,
            distributionPeriod: distributionPeriod,
            transferRestricted: transferRestricted
        });
    }

    function remainingSupply() external view returns (uint256) {
        return maxSupply - totalSupply();
    }

    function _update(address from, address to, uint256 value) internal override {
        if (transferRestricted && from != address(0) && to != address(0) && !transferWhitelist[to]) {
            revert TransferRestricted();
        }
        super._update(from, to, value);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) { }
}
