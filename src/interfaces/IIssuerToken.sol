// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIssuerToken {
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

    struct IssuerTerms {
        uint256 profitSharingRatio;
        uint256 totalSupply;
        uint256 pricePerUnit;
        string distributionPeriod;
        bool transferRestricted;
    }

    event Purchase(address indexed investor, uint256 amount, string paymentSource, uint256 timestamp);
    event TransferWhitelistUpdated(address indexed account, bool allowed);
    event TransferRestrictionUpdated(bool restricted);

    function initialize(InitParams calldata params) external;

    function purchaseTokens(address investorAddress, uint256 amount, string calldata paymentSource) external;

    function setTransferWhitelist(address account, bool allowed) external;

    function setTransferRestricted(bool restricted) external;

    function getIssuerTerms() external view returns (IssuerTerms memory);

    function remainingSupply() external view returns (uint256);
}
