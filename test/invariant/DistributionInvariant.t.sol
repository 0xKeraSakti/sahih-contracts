// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Distribution } from "../../src/Distribution.sol";
import { IDistribution } from "../../src/interfaces/IDistribution.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { DeployHelpers } from "../helpers/DeployHelpers.sol";

contract DistributionHandler is Test {
    Distribution public immutable DISTRIBUTION;
    MockToken public immutable PAYMENT_TOKEN;
    address public immutable ISSUER_CONTRACT;
    address public immutable HOLDER_A;
    address public immutable HOLDER_B;

    uint256 public totalDistributed;
    uint256 public periodCounter;
    uint256 public callCount;

    constructor(
        Distribution distribution_,
        MockToken paymentToken_,
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

    function recordDistribution(uint256 amountSeed) external {
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

contract DistributionInvariantTest is Test, DeployHelpers {
    Distribution internal distribution;
    MockToken internal paymentToken;
    DistributionHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal issuerContract = makeAddr("issuerContract");
    address internal holderA = makeAddr("holderA");
    address internal holderB = makeAddr("holderB");

    uint256 internal funding = 100_000_000;

    function setUp() public {
        (distribution, paymentToken) = deployDistribution(admin, operator);
        paymentToken.mint(address(distribution), funding);

        handler = new DistributionHandler(distribution, paymentToken, issuerContract, holderA, holderB);

        vm.prank(admin);
        distribution.grantRole(distribution.OPERATOR_ROLE(), address(handler));

        targetContract(address(handler));
    }

    function invariant_ContractBalanceMatchesDistributedTotal() public view {
        assertEq(paymentToken.balanceOf(address(distribution)), funding - handler.totalDistributed());
    }

    function invariant_HolderBalancesSumToDistributedTotal() public view {
        assertEq(
            paymentToken.balanceOf(holderA) + paymentToken.balanceOf(holderB) + paymentToken.balanceOf(
                address(distribution)
            ),
            funding
        );
    }

    function invariant_RecordedPeriodsMatchSuccessfulCalls() public view {
        assertEq(distribution.getRecordedPeriods(issuerContract).length, handler.callCount());
    }

    function invariant_NeverDistributesMoreThanFunded() public view {
        assertLe(handler.totalDistributed(), funding);
    }
}
