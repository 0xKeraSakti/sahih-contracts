// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDistribution } from "./interfaces/IDistribution.sol";
import { PeriodLib } from "./libraries/PeriodLib.sol";

/// @title Distribution
/// @author Sahih Contracts
/// @notice Records and pays out profit-sharing distributions to investors
contract Distribution is IDistribution, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using PeriodLib for string;

    /// @notice Role allowed to update the payment token
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role allowed to record distributions
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Maximum number of holders that can be paid in a single distribution
    uint256 public constant MAX_HOLDERS_PER_DISTRIBUTION = 100;

    /// @notice ERC20 token used to pay out distributions
    IERC20 public paymentToken;
    /// @notice Distribution record for a given issuer contract and period
    mapping(address => mapping(string => DistributionRecord)) private distributionHistory;
    /// @notice Periods recorded for a given issuer contract
    mapping(address => string[]) private _issuerPeriods;
    /// @notice Distributions paid to a given investor address
    mapping(address => InvestorDistribution[]) private _investorDistributions;

    uint256[50] private __gap;

    error ZeroAddress();
    error EmptyPeriod();
    error InvalidHolder(uint256 index);
    error TooManyHolders(uint256 provided, uint256 maximum);
    error PeriodAlreadyRecorded(address issuerContract, string period);
    error DistributionTotalMismatch(uint256 expected, uint256 actual);
    error InsufficientBalance(uint256 required, uint256 available);

    /// @notice Disables initializers on the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract, setting the payment token and roles
    /// @param paymentToken_ ERC20 token used to pay out distributions
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    function initialize(
        address paymentToken_,
        address admin,
        address operator
    ) external initializer {
        if (paymentToken_ == address(0) || admin == address(0) || operator == address(0)) {
            revert ZeroAddress();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);

        paymentToken = IERC20(paymentToken_);

        emit PaymentTokenUpdated(paymentToken_);
    }

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
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        _validateDistribution(issuerContract, period, distributions, totalAmount);

        uint256 distributedAt = block.timestamp;
        _storeDistribution(issuerContract, period, distributions, totalAmount, calculationRefHash, distributedAt);

        emit Distributed(issuerContract, period, totalAmount, distributedAt);

        _payoutHolders(distributions);
    }

    /// @notice Updates the ERC20 token used to pay out distributions
    /// @param paymentToken_ New payment token address
    function setPaymentToken(
        address paymentToken_
    ) external onlyRole(ADMIN_ROLE) {
        if (paymentToken_ == address(0)) {
            revert ZeroAddress();
        }
        paymentToken = IERC20(paymentToken_);

        emit PaymentTokenUpdated(paymentToken_);
    }

    /// @notice Lists recorded distribution summaries for an issuer within a period range, inclusive
    /// @param issuerContract Address of the issuer token contract to query
    /// @param fromPeriod Earliest period to include
    /// @param toPeriod Latest period to include
    /// @return history Distribution summaries for periods within the range
    function getDistributionHistory(
        address issuerContract,
        string calldata fromPeriod,
        string calldata toPeriod
    ) external view returns (PeriodSummary[] memory history) {
        string[] memory periods = _issuerPeriods[issuerContract];
        uint256 matched = 0;

        for (uint256 i = 0; i < periods.length; ++i) {
            if (periods[i].isWithin(fromPeriod, toPeriod)) {
                ++matched;
            }
        }

        history = new PeriodSummary[](matched);
        uint256 cursor = 0;

        for (uint256 i = 0; i < periods.length; ++i) {
            if (periods[i].isWithin(fromPeriod, toPeriod)) {
                DistributionRecord memory record = distributionHistory[issuerContract][periods[i]];
                history[cursor] = PeriodSummary({
                    period: record.period,
                    totalAmount: record.totalAmount,
                    distributedAt: record.distributedAt,
                    calculationRefHash: record.calculationRefHash
                });
                ++cursor;
            }
        }
    }

    /// @notice Lists all distributions paid to a given investor
    /// @param investorAddress Address of the investor to query
    /// @return All distributions paid to the investor across issuers and periods
    function getInvestorDistributions(
        address investorAddress
    ) external view returns (InvestorDistribution[] memory) {
        return _investorDistributions[investorAddress];
    }

    /// @notice Lists all period identifiers recorded for an issuer
    /// @param issuerContract Address of the issuer token contract to query
    /// @return Recorded period identifiers
    function getRecordedPeriods(
        address issuerContract
    ) external view returns (string[] memory) {
        return _issuerPeriods[issuerContract];
    }

    /// @notice Fetches the distribution record for an issuer's period
    /// @param issuerContract Address of the issuer token contract to query
    /// @param period Period identifier to query
    /// @return The distribution record for the given issuer and period
    function getDistributionRecord(
        address issuerContract,
        string calldata period
    ) external view returns (DistributionRecord memory) {
        return distributionHistory[issuerContract][period];
    }

    // solhint-disable no-empty-blocks
    /// @notice Authorizes a UUPS upgrade; restricted to the admin role
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

    // solhint-enable no-empty-blocks

    /// @notice Persists the distribution record and each holder's distribution entry
    /// @param issuerContract Address of the issuer token contract the distribution is for
    /// @param period Period identifier the distribution covers
    /// @param distributions Holder addresses and their payout amounts
    /// @param totalAmount Total amount being distributed
    /// @param calculationRefHash Reference hash of the off-chain calculation backing this distribution
    /// @param distributedAt Timestamp the distribution is recorded at
    function _storeDistribution(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount,
        bytes32 calculationRefHash,
        uint256 distributedAt
    ) private {
        distributionHistory[issuerContract][period] = DistributionRecord({
            period: period,
            totalAmount: totalAmount,
            distributedAt: distributedAt,
            calculationRefHash: calculationRefHash,
            recorded: true
        });
        _issuerPeriods[issuerContract].push(period);

        for (uint256 i = 0; i < distributions.length; ++i) {
            _investorDistributions[distributions[i].holderAddress].push(
                InvestorDistribution({
                    issuerContract: issuerContract,
                    period: period,
                    amount: distributions[i].amount,
                    distributedAt: distributedAt
                })
            );
        }
    }

    /// @notice Transfers the payout amount to each holder
    /// @param distributions Holder addresses and their payout amounts
    function _payoutHolders(
        HolderAmount[] calldata distributions
    ) private {
        for (uint256 i = 0; i < distributions.length; ++i) {
            if (distributions[i].amount > 0) {
                paymentToken.safeTransfer(distributions[i].holderAddress, distributions[i].amount);
            }
        }
    }

    /// @notice Validates a distribution request before it is recorded
    /// @param issuerContract Address of the issuer token contract the distribution is for
    /// @param period Period identifier the distribution covers
    /// @param distributions Holder addresses and their payout amounts
    /// @param totalAmount Total amount being distributed, must equal the sum of `distributions`
    function _validateDistribution(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount
    ) private view {
        if (issuerContract == address(0)) {
            revert ZeroAddress();
        }
        if (period.isEmpty()) {
            revert EmptyPeriod();
        }
        if (distributions.length > MAX_HOLDERS_PER_DISTRIBUTION) {
            revert TooManyHolders(distributions.length, MAX_HOLDERS_PER_DISTRIBUTION);
        }
        if (distributionHistory[issuerContract][period].recorded) {
            revert PeriodAlreadyRecorded(issuerContract, period);
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < distributions.length; ++i) {
            if (distributions[i].holderAddress == address(0)) {
                revert InvalidHolder(i);
            }
            sum += distributions[i].amount;
        }
        if (sum != totalAmount) {
            revert DistributionTotalMismatch(totalAmount, sum);
        }

        uint256 available = paymentToken.balanceOf(address(this));
        if (available < totalAmount) {
            revert InsufficientBalance(totalAmount, available);
        }
    }
}
