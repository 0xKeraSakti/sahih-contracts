// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IssuerToken } from "../../src/IssuerToken.sol";

contract IssuerTokenV2 is IssuerToken {
    string public constant VERSION = "v2";

    uint256 public secondaryMarketFeeBps;

    event SecondaryMarketFeeUpdated(uint256 feeBps);

    error FeeTooHigh(uint256 feeBps);

    function setSecondaryMarketFee(uint256 feeBps) external onlyRole(ADMIN_ROLE) {
        if (feeBps > 10_000) {
            revert FeeTooHigh(feeBps);
        }
        secondaryMarketFeeBps = feeBps;

        emit SecondaryMarketFeeUpdated(feeBps);
    }
}
