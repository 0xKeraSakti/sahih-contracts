// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDistribution } from "./interfaces/IDistribution.sol";
import { PeriodLib } from "./libraries/PeriodLib.sol";

contract Distribution is IDistribution, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using PeriodLib for string;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MAX_HOLDERS_PER_DISTRIBUTION = 100;

    IERC20 public paymentToken;
    mapping(address => mapping(string => DistributionRecord)) private distributionHistory;
    mapping(address => string[]) private _issuerPeriods;
    mapping(address => InvestorDistribution[]) private _investorDistributions;

    uint256[50] private __gap;

    error ZeroAddress();
    error EmptyPeriod();
    error InvalidHolder(uint256 index);
    error TooManyHolders(uint256 provided, uint256 maximum);
    error PeriodAlreadyRecorded(address issuerContract, string period);
    error DistributionTotalMismatch(uint256 expected, uint256 actual);
    error InsufficientBalance(uint256 required, uint256 available);

    constructor() {
        _disableInitializers();
    }

    function initialize(address paymentToken_, address admin, address operator) external initializer {
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

    function recordDistribution(
        address issuerContract,
        string calldata period,
        HolderAmount[] calldata distributions,
        uint256 totalAmount,
        bytes32 calculationRefHash
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
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
        for (uint256 i = 0; i < distributions.length; i++) {
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

        uint256 distributedAt = block.timestamp;

        distributionHistory[issuerContract][period] = DistributionRecord({
            period: period,
            totalAmount: totalAmount,
            distributedAt: distributedAt,
            calculationRefHash: calculationRefHash,
            recorded: true
        });
        _issuerPeriods[issuerContract].push(period);

        for (uint256 i = 0; i < distributions.length; i++) {
            _investorDistributions[distributions[i].holderAddress].push(
                InvestorDistribution({
                    issuerContract: issuerContract,
                    period: period,
                    amount: distributions[i].amount,
                    distributedAt: distributedAt
                })
            );
        }

        emit Distributed(issuerContract, period, totalAmount, distributedAt);

        for (uint256 i = 0; i < distributions.length; i++) {
            if (distributions[i].amount > 0) {
                paymentToken.safeTransfer(distributions[i].holderAddress, distributions[i].amount);
            }
        }
    }

    function setPaymentToken(address paymentToken_) external onlyRole(ADMIN_ROLE) {
        if (paymentToken_ == address(0)) {
            revert ZeroAddress();
        }
        paymentToken = IERC20(paymentToken_);

        emit PaymentTokenUpdated(paymentToken_);
    }

    function getDistributionHistory(address issuerContract, string calldata fromPeriod, string calldata toPeriod)
        external
        view
        returns (PeriodSummary[] memory history)
    {
        string[] memory periods = _issuerPeriods[issuerContract];
        uint256 matched = 0;

        for (uint256 i = 0; i < periods.length; i++) {
            if (periods[i].isWithin(fromPeriod, toPeriod)) {
                matched++;
            }
        }

        history = new PeriodSummary[](matched);
        uint256 cursor = 0;

        for (uint256 i = 0; i < periods.length; i++) {
            if (periods[i].isWithin(fromPeriod, toPeriod)) {
                DistributionRecord memory record = distributionHistory[issuerContract][periods[i]];
                history[cursor] = PeriodSummary({
                    period: record.period,
                    totalAmount: record.totalAmount,
                    distributedAt: record.distributedAt,
                    calculationRefHash: record.calculationRefHash
                });
                cursor++;
            }
        }
    }

    function getInvestorDistributions(address investorAddress)
        external
        view
        returns (InvestorDistribution[] memory)
    {
        return _investorDistributions[investorAddress];
    }

    function getRecordedPeriods(address issuerContract) external view returns (string[] memory) {
        return _issuerPeriods[issuerContract];
    }

    function getDistributionRecord(address issuerContract, string calldata period)
        external
        view
        returns (DistributionRecord memory)
    {
        return distributionHistory[issuerContract][period];
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) { }
}
