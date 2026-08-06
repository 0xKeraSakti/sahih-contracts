// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistribution
/// @author Sahih Contracts
/// @notice Interface for recording and paying out profit-sharing distributions to investors
interface IDistribution {
    /// @notice A holder address and the amount to pay them in a distribution
    struct HolderAmount {
        address holderAddress;
        uint256 amount;
    }

    /// @notice A recorded distribution for an issuer's period
    struct DistributionRecord {
        string period;
        uint256 totalAmount;
        uint256 distributedAt;
        bytes32 calculationRefHash;
        bool recorded;
    }

    /// @notice A distribution entry paid to a specific investor
    struct InvestorDistribution {
        address issuerContract;
        string period;
        uint256 amount;
        uint256 distributedAt;
    }

    /// @notice Summary of a distribution record, used for range queries
    struct PeriodSummary {
        string period;
        uint256 totalAmount;
        uint256 distributedAt;
        bytes32 calculationRefHash;
    }

    /// @notice Emitted when a distribution is recorded and paid out
    /// @param issuerContract Issuer token contract the distribution is for
    /// @param period Period identifier the distribution covers
    /// @param totalAmount Total amount distributed
    /// @param timestamp Timestamp the distribution was recorded
    event Distributed(
        address indexed issuerContract, string indexed period, uint256 indexed totalAmount, uint256 timestamp
    );
    /// @notice Emitted when the payment token is updated
    /// @param paymentToken New payment token address
    event PaymentTokenUpdated(address indexed paymentToken);

    /// @notice Initializes the contract, setting the payment token and roles
    /// @param paymentToken_ ERC20 token used to pay out distributions
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    function initialize(
        address paymentToken_,
        address admin,
        address operator
    ) external;

    /// @notice Records a distribution for an issuer's period and pays out each holder
    /// @param issuerContract Address of the issuer token contract the distribution is for
    /// @param period Period identifier the distribution covers
    /// @param distributions Holder addresses and their payout amounts
    /// @param totalAmount Total amount being distributed, must equal the sum of `distributions`
    /// @param calculationRefHash Reference hash of the off-chain calculation backing this distribution
    function recordDistribution(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount,
        bytes32 calculationRefHash
    ) external;

    /// @notice Updates the ERC20 token used to pay out distributions
    /// @param paymentToken_ New payment token address
    function setPaymentToken(
        address paymentToken_
    ) external;

    /// @notice Lists recorded distribution summaries for an issuer within a period range, inclusive
    /// @param issuerContract Address of the issuer token contract to query
    /// @param fromPeriod Earliest period to include
    /// @param toPeriod Latest period to include
    /// @return Distribution summaries for periods within the range
    function getDistributionHistory(
        address issuerContract,
        string calldata fromPeriod,
        string calldata toPeriod
    ) external view returns (PeriodSummary[] memory);

    /// @notice Lists all distributions paid to a given investor
    /// @param investorAddress Address of the investor to query
    /// @return All distributions paid to the investor across issuers and periods
    function getInvestorDistributions(
        address investorAddress
    ) external view returns (InvestorDistribution[] memory);

    /// @notice Lists all period identifiers recorded for an issuer
    /// @param issuerContract Address of the issuer token contract to query
    /// @return Recorded period identifiers
    function getRecordedPeriods(
        address issuerContract
    ) external view returns (string[] memory);

    /// @notice Fetches the distribution record for an issuer's period
    /// @param issuerContract Address of the issuer token contract to query
    /// @param period Period identifier to query
    /// @return The distribution record for the given issuer and period
    function getDistributionRecord(
        address issuerContract,
        string calldata period
    ) external view returns (DistributionRecord memory);
}
