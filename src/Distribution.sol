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
    /// @notice Byte length of the period identifiers recorded for a given issuer contract
    mapping(address => uint256) private _issuerPeriodLength;
    /// @notice Whether a given batch of an issuer's period has already been recorded
    mapping(address => mapping(string => mapping(uint256 => bool))) private _recordedBatches;
    /// @notice Running total distributed for a given issuer contract, across all periods and batches
    mapping(address => uint256) public totalDistributedByIssuer;

    uint256[47] private __gap;

    error ZeroAddress();
    error EmptyPeriod();
    error PeriodLengthMismatch(uint256 expected, uint256 actual);
    error InvalidHolder(uint256 index);
    error TooManyHolders(uint256 provided, uint256 maximum);
    error BatchAlreadyRecorded(address issuerContract, string period, uint256 batchIndex);
    error CalculationRefMismatch(bytes32 expected, bytes32 actual);
    error DistributionTotalMismatch(uint256 expected, uint256 actual);
    error InsufficientBalance(uint256 required, uint256 available);
    error InvalidPagination(uint256 offset, uint256 limit);

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
        _recordDistribution(issuerContract, period, distributions, totalAmount, calculationRefHash, 0);
    }

    /// @notice Records one batch of a period's distribution and pays out that batch's holders
    /// @dev Use when a period has more holders than `MAX_HOLDERS_PER_DISTRIBUTION`. Each batch of the
    /// same period may only be recorded once, so a retry that reuses `batchIndex` reverts rather than
    /// paying twice. Amounts accumulate into the period's single record
    /// @param issuerContract Address of the issuer token contract the distribution is for
    /// @param period Period identifier the distribution covers
    /// @param distributions Holder addresses and their payout amounts for this batch only
    /// @param totalAmount Total for this batch, must equal the sum of `distributions`
    /// @param calculationRefHash Reference hash of the off-chain calculation; must match across batches
    /// @param batchIndex Zero-based index of this batch within the period
    function recordDistributionBatch(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount,
        bytes32 calculationRefHash,
        uint256 batchIndex
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        _recordDistribution(issuerContract, period, distributions, totalAmount, calculationRefHash, batchIndex);
    }

    /// @notice Rescues ERC20 tokens held by this contract
    /// @dev Covers over-funding and balances orphaned by `setPaymentToken`, which would otherwise be
    /// locked permanently. Note this can also move funds earmarked for an upcoming distribution
    /// @param token Address of the ERC20 token to rescue
    /// @param to Address to send the rescued tokens to
    /// @param amount Amount to rescue
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (token == address(0) || to == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(to, amount);

        emit TokensRescued(token, to, amount);
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

    /// @notice Checks whether a specific batch of a period has already been recorded
    /// @param issuerContract Address of the issuer token contract to query
    /// @param period Period identifier to query
    /// @param batchIndex Zero-based batch index to check
    /// @return True if that batch has been recorded
    function isBatchRecorded(
        address issuerContract,
        string calldata period,
        uint256 batchIndex
    ) external view returns (bool) {
        return _recordedBatches[issuerContract][period][batchIndex];
    }

    /// @notice Returns how many distributions an investor has received
    /// @param investorAddress Address of the investor to query
    /// @return Number of distribution entries recorded for the investor
    function getInvestorDistributionCount(
        address investorAddress
    ) external view returns (uint256) {
        return _investorDistributions[investorAddress].length;
    }

    /// @notice Lists an investor's distributions one page at a time
    /// @dev Prefer this over `getInvestorDistributions` for accounts with long histories, whose full
    /// array can grow past what an RPC call will return
    /// @param investorAddress Address of the investor to query
    /// @param offset Index to start from
    /// @param limit Maximum number of entries to return
    /// @return page Distribution entries within the requested window
    function getInvestorDistributionsPaged(
        address investorAddress,
        uint256 offset,
        uint256 limit
    ) external view returns (InvestorDistribution[] memory page) {
        if (limit == 0) {
            revert InvalidPagination(offset, limit);
        }

        InvestorDistribution[] storage entries = _investorDistributions[investorAddress];
        uint256 total = entries.length;
        if (offset >= total) {
            return new InvestorDistribution[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        page = new InvestorDistribution[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = entries[i];
        }
    }

    /// @notice Returns how many periods have been recorded for an issuer
    /// @param issuerContract Address of the issuer token contract to query
    /// @return Number of recorded periods
    function getRecordedPeriodCount(
        address issuerContract
    ) external view returns (uint256) {
        return _issuerPeriods[issuerContract].length;
    }

    /// @notice Lists an issuer's recorded periods one page at a time
    /// @param issuerContract Address of the issuer token contract to query
    /// @param offset Index to start from
    /// @param limit Maximum number of entries to return
    /// @return page Period identifiers within the requested window
    function getRecordedPeriodsPaged(
        address issuerContract,
        uint256 offset,
        uint256 limit
    ) external view returns (string[] memory page) {
        if (limit == 0) {
            revert InvalidPagination(offset, limit);
        }

        string[] storage periods = _issuerPeriods[issuerContract];
        uint256 total = periods.length;
        if (offset >= total) {
            return new string[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        page = new string[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = periods[i];
        }
    }

    // solhint-disable no-empty-blocks
    /// @notice Authorizes a UUPS upgrade; restricted to the admin role
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

    // solhint-enable no-empty-blocks

    /// @notice Validates, records, and pays out one batch of a period's distribution
    /// @param issuerContract Address of the issuer token contract the distribution is for
    /// @param period Period identifier the distribution covers
    /// @param distributions Holder addresses and their payout amounts for this batch
    /// @param totalAmount Total for this batch, must equal the sum of `distributions`
    /// @param calculationRefHash Reference hash of the off-chain calculation backing this distribution
    /// @param batchIndex Zero-based index of this batch within the period
    function _recordDistribution(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount,
        bytes32 calculationRefHash,
        uint256 batchIndex
    ) private {
        _validateDistribution(issuerContract, period, distributions, totalAmount, calculationRefHash, batchIndex);

        uint256 distributedAt = block.timestamp;
        _storeDistribution(
            issuerContract, period, distributions, totalAmount, calculationRefHash, distributedAt, batchIndex
        );

        emit Distributed(issuerContract, keccak256(bytes(period)), period, totalAmount, batchIndex, distributedAt);

        _payoutHolders(distributions);
    }

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
        uint256 distributedAt,
        uint256 batchIndex
    ) private {
        DistributionRecord storage record = distributionHistory[issuerContract][period];

        if (record.recorded) {
            // Later batches of a period add to the record the first batch created; `distributedAt`
            // deliberately keeps pointing at when the period's distribution started
            record.totalAmount += totalAmount;
        } else {
            distributionHistory[issuerContract][period] = DistributionRecord({
                period: period,
                totalAmount: totalAmount,
                distributedAt: distributedAt,
                calculationRefHash: calculationRefHash,
                recorded: true
            });
            _issuerPeriods[issuerContract].push(period);
            if (_issuerPeriodLength[issuerContract] == 0) {
                _issuerPeriodLength[issuerContract] = bytes(period).length;
            }
        }

        _recordedBatches[issuerContract][period][batchIndex] = true;
        totalDistributedByIssuer[issuerContract] += totalAmount;

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
        uint256 totalAmount,
        bytes32 calculationRefHash,
        uint256 batchIndex
    ) private view {
        if (issuerContract == address(0)) {
            revert ZeroAddress();
        }
        if (period.isEmpty()) {
            revert EmptyPeriod();
        }
        // Period ranges are compared lexicographically (see PeriodLib), which only orders correctly when
        // every identifier is the same width. Pinning the width to the first period recorded for an issuer
        // rejects unpadded identifiers such as "2026-W5" without hardcoding a single period format
        uint256 expectedLength = _issuerPeriodLength[issuerContract];
        if (expectedLength != 0 && bytes(period).length != expectedLength) {
            revert PeriodLengthMismatch(expectedLength, bytes(period).length);
        }
        if (distributions.length > MAX_HOLDERS_PER_DISTRIBUTION) {
            revert TooManyHolders(distributions.length, MAX_HOLDERS_PER_DISTRIBUTION);
        }
        if (_recordedBatches[issuerContract][period][batchIndex]) {
            revert BatchAlreadyRecorded(issuerContract, period, batchIndex);
        }
        // Every batch of a period must cite the same off-chain calculation, so a period can never end
        // up split across two contradictory sets of numbers
        DistributionRecord storage record = distributionHistory[issuerContract][period];
        if (record.recorded && record.calculationRefHash != calculationRefHash) {
            revert CalculationRefMismatch(record.calculationRefHash, calculationRefHash);
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
