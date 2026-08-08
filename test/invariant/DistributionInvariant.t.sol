// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Distribution } from "../../src/Distribution.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { DemoPaymentToken } from "../../src/DemoPaymentToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

/// @title DistributionHandler
/// @author Sahih Contracts
/// @notice Invariant test handler that drives randomized recordDistribution calls against a Distribution contract
contract DistributionHandler is Test {
    /// @notice The Distribution contract under test
    Distribution public immutable DISTRIBUTION;
    /// @notice The payment token used for distributions
    DemoPaymentToken public immutable PAYMENT_TOKEN;
    /// @notice The issuer contract address used for all recorded distributions
    address public immutable ISSUER_CONTRACT;
    /// @notice The first holder address that receives a share of each distribution
    address public immutable HOLDER_A;
    /// @notice The second holder address that receives a share of each distribution
    address public immutable HOLDER_B;

    /// @notice Running total of all amounts successfully distributed
    uint256 public totalDistributed;
    /// @notice Counter used to generate a unique period string for each call
    uint256 public periodCounter;
    /// @notice Number of times recordDistribution has been successfully called
    uint256 public callCount;

    /// @notice Stores the Distribution contract and fixed addresses used across all handler calls
    /// @param distribution_ The Distribution contract to drive
    /// @param paymentToken_ The payment token used for distributions
    /// @param issuerContract_ The issuer contract address used for all recorded distributions
    /// @param holderA_ The first holder address
    /// @param holderB_ The second holder address
    constructor(
        Distribution distribution_,
        DemoPaymentToken paymentToken_,
        address issuerContract_,
        address holderA_,
        address holderB_
    ) {
        DISTRIBUTION = distribution_;
        PAYMENT_TOKEN = paymentToken_;
        ISSUER_CONTRACT = issuerContract_;
        HOLDER_A = holderA_;
        HOLDER_B = holderB_;
    }

    /// @notice Records a randomized distribution split between the two fixed holders for a new period
    /// @param amountSeed Fuzzed seed used to derive the total amount to distribute
    function recordDistribution(
        uint256 amountSeed
    ) external {
        uint256 amount = amountSeed % 1_000_000;
        uint256 amountA = amount / 2;
        uint256 amountB = amount - amountA;

        periodCounter++;
        string memory period = string.concat("2026-W", vm.toString(periodCounter));

        IDistribution.HolderAmount[] memory holders = new IDistribution.HolderAmount[](2);
        holders[0] = IDistribution.HolderAmount({ holderAddress: HOLDER_A, amount: amountA });
        holders[1] = IDistribution.HolderAmount({ holderAddress: HOLDER_B, amount: amountB });

        DISTRIBUTION.recordDistribution(ISSUER_CONTRACT, period, holders, amount, keccak256(abi.encode(period)));

        totalDistributed += amount;
        callCount++;
    }
}

/// @title DistributionInvariantTest
/// @author Sahih Contracts
/// @notice Invariant tests verifying Distribution's accounting stays consistent under randomized calls
contract DistributionInvariantTest is Test, DeployHelpers {
    Distribution internal distribution;
    DemoPaymentToken internal paymentToken;
    DistributionHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal issuerContract = makeAddr("issuerContract");
    address internal holderA = makeAddr("holderA");
    address internal holderB = makeAddr("holderB");

    uint256 internal funding = 100_000_000;

    /// @notice Deploys Distribution, funds it, and wires up the DistributionHandler as the fuzz target before each run
    function setUp() public {
        (distribution, paymentToken) = deployDistribution(admin, operator);
        paymentToken.mint(address(distribution), funding);

        handler = new DistributionHandler(distribution, paymentToken, issuerContract, holderA, holderB);

        bytes32 operatorRole = distribution.OPERATOR_ROLE();
        vm.prank(admin);
        distribution.grantRole(operatorRole, address(handler));

        targetContract(address(handler));
    }

    /// @notice The Distribution contract's token balance always equals the initial funding minus what has been distributed
    function invariant_ContractBalanceMatchesDistributedTotal() public view {
        assertEq(paymentToken.balanceOf(address(distribution)), funding - handler.totalDistributed());
    }

    /// @notice The sum of holder balances plus the remaining contract balance always equals the initial funding
    function invariant_HolderBalancesSumToDistributedTotal() public view {
        assertEq(
            paymentToken.balanceOf(holderA) + paymentToken.balanceOf(holderB)
                + paymentToken.balanceOf(address(distribution)),
            funding
        );
    }

    /// @notice The number of recorded periods for the issuer always matches the number of successful handler calls
    function invariant_RecordedPeriodsMatchSuccessfulCalls() public view {
        assertEq(distribution.getRecordedPeriods(issuerContract).length, handler.callCount());
    }

    /// @notice The total amount distributed never exceeds the amount the contract was originally funded with
    function invariant_NeverDistributesMoreThanFunded() public view {
        assertLe(handler.totalDistributed(), funding);
    }
}
