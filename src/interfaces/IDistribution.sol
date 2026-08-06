// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDistribution {
    struct HolderAmount {
        address holderAddress;
        uint256 amount;
    }

    struct DistributionRecord {
        string period;
        uint256 totalAmount;
        uint256 distributedAt;
        bytes32 calculationRefHash;
        bool recorded;
    }

    struct InvestorDistribution {
        address issuerContract;
        string period;
        uint256 amount;
        uint256 distributedAt;
    }

    struct PeriodSummary {
        string period;
        uint256 totalAmount;
        uint256 distributedAt;
        bytes32 calculationRefHash;
    }

    event Distributed(address indexed issuerContract, string period, uint256 totalAmount, uint256 timestamp);
    event PaymentTokenUpdated(address indexed paymentToken);

    function initialize(address paymentToken_, address admin, address operator) external;

    function recordDistribution(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount,
        bytes32 calculationRefHash
    ) external;

    function setPaymentToken(address paymentToken_) external;

    function getDistributionHistory(address issuerContract, string calldata fromPeriod, string calldata toPeriod)
        external
        view
        returns (PeriodSummary[] memory);

    function getInvestorDistributions(address investorAddress)
        external
        view
        returns (InvestorDistribution[] memory);

    function getRecordedPeriods(address issuerContract) external view returns (string[] memory);

    function getDistributionRecord(address issuerContract, string calldata period)
        external
        view
        returns (DistributionRecord memory);
}
