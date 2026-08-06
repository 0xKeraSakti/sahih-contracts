// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IIssuerToken } from "./interfaces/IIssuerToken.sol";
import { PeriodLib } from "./libraries/PeriodLib.sol";

contract Factory is AccessControl {
    using PeriodLib for string;

    struct CreateIssuerTokenParams {
        string issuerId;
        string tokenName;
        string tokenSymbol;
        uint256 totalSupply;
        uint256 pricePerUnit;
        uint256 profitSharingRatio;
        string distributionPeriod;
        bool transferRestricted;
    }

    struct IssuerMeta {
        string issuerId;
        uint256 deployedAt;
        bool active;
    }

    struct IssuerSummary {
        string issuerId;
        address contractAddress;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MAX_PROFIT_SHARING_RATIO = 10_000;

    mapping(string => address) public issuerContracts;
    mapping(address => IssuerMeta) private issuerMeta;
    address[] public allIssuerContracts;
    address public tokenImplementation;
    address public tokenAdmin;
    address public tokenOperator;

    event IssuerTokenCreated(string indexed issuerId, address indexed contractAddress, uint256 timestamp);
    event TokenImplementationUpdated(address indexed tokenImplementation);
    event TokenRolesUpdated(address indexed tokenAdmin, address indexed tokenOperator);
    event IssuerStatusUpdated(string indexed issuerId, address indexed contractAddress, bool active);

    error ZeroAddress();
    error EmptyIssuerId();
    error IssuerAlreadyRegistered(string issuerId);
    error IssuerNotFound(string issuerId);
    error InvalidProfitSharingRatio(uint256 ratio);
    error InvalidTotalSupply();
    error InvalidPricePerUnit();
    error InvalidPagination(uint256 page, uint256 limit);

    constructor(address tokenImplementation_, address admin, address operator) {
        if (tokenImplementation_ == address(0) || admin == address(0) || operator == address(0)) {
            revert ZeroAddress();
        }

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);

        tokenImplementation = tokenImplementation_;
        tokenAdmin = admin;
        tokenOperator = operator;
    }

    function createIssuerToken(CreateIssuerTokenParams calldata params)
        external
        onlyRole(OPERATOR_ROLE)
        returns (address contractAddress, uint256 deployedAt)
    {
        if (params.issuerId.isEmpty()) {
            revert EmptyIssuerId();
        }
        if (issuerContracts[params.issuerId] != address(0)) {
            revert IssuerAlreadyRegistered(params.issuerId);
        }
        if (params.totalSupply == 0) {
            revert InvalidTotalSupply();
        }
        if (params.pricePerUnit == 0) {
            revert InvalidPricePerUnit();
        }
        if (params.profitSharingRatio == 0 || params.profitSharingRatio > MAX_PROFIT_SHARING_RATIO) {
            revert InvalidProfitSharingRatio(params.profitSharingRatio);
        }

        IIssuerToken.InitParams memory initParams = IIssuerToken.InitParams({
            issuerId: params.issuerId,
            tokenName: params.tokenName,
            tokenSymbol: params.tokenSymbol,
            maxSupply: params.totalSupply,
            pricePerUnit: params.pricePerUnit,
            profitSharingRatio: params.profitSharingRatio,
            distributionPeriod: params.distributionPeriod,
            transferRestricted: params.transferRestricted,
            admin: tokenAdmin,
            operator: tokenOperator
        });

        bytes memory initData = abi.encodeCall(IIssuerToken.initialize, (initParams));
        contractAddress = address(new ERC1967Proxy(tokenImplementation, initData));
        deployedAt = block.timestamp;

        issuerContracts[params.issuerId] = contractAddress;
        issuerMeta[contractAddress] = IssuerMeta({ issuerId: params.issuerId, deployedAt: deployedAt, active: true });
        allIssuerContracts.push(contractAddress);

        emit IssuerTokenCreated(params.issuerId, contractAddress, deployedAt);
    }

    function setTokenImplementation(address tokenImplementation_) external onlyRole(ADMIN_ROLE) {
        if (tokenImplementation_ == address(0)) {
            revert ZeroAddress();
        }
        tokenImplementation = tokenImplementation_;

        emit TokenImplementationUpdated(tokenImplementation_);
    }

    function setTokenRoles(address tokenAdmin_, address tokenOperator_) external onlyRole(ADMIN_ROLE) {
        if (tokenAdmin_ == address(0) || tokenOperator_ == address(0)) {
            revert ZeroAddress();
        }
        tokenAdmin = tokenAdmin_;
        tokenOperator = tokenOperator_;

        emit TokenRolesUpdated(tokenAdmin_, tokenOperator_);
    }

    function setIssuerStatus(string calldata issuerId, bool active) external onlyRole(ADMIN_ROLE) {
        address contractAddress = issuerContracts[issuerId];
        if (contractAddress == address(0)) {
            revert IssuerNotFound(issuerId);
        }
        issuerMeta[contractAddress].active = active;

        emit IssuerStatusUpdated(issuerId, contractAddress, active);
    }

    function getIssuerContract(string calldata issuerId)
        external
        view
        returns (address contractAddress, uint256 deployedAt, bool active)
    {
        contractAddress = issuerContracts[issuerId];
        if (contractAddress == address(0)) {
            revert IssuerNotFound(issuerId);
        }

        IssuerMeta memory meta = issuerMeta[contractAddress];
        deployedAt = meta.deployedAt;
        active = meta.active;
    }

    function listAllIssuers(uint256 page, uint256 limit)
        external
        view
        returns (IssuerSummary[] memory issuers, uint256 totalCount)
    {
        if (page == 0 || limit == 0) {
            revert InvalidPagination(page, limit);
        }

        totalCount = allIssuerContracts.length;
        uint256 start = (page - 1) * limit;
        if (start >= totalCount) {
            return (new IssuerSummary[](0), totalCount);
        }

        uint256 end = start + limit;
        if (end > totalCount) {
            end = totalCount;
        }

        issuers = new IssuerSummary[](end - start);
        for (uint256 i = start; i < end; i++) {
            address contractAddress = allIssuerContracts[i];
            issuers[i - start] =
                IssuerSummary({ issuerId: issuerMeta[contractAddress].issuerId, contractAddress: contractAddress });
        }
    }

    function totalIssuers() external view returns (uint256) {
        return allIssuerContracts.length;
    }
}
