// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IIssuerToken } from "./interfaces/IIssuerToken.sol";
import { PeriodLib } from "./libraries/PeriodLib.sol";

/// @title Factory
/// @author Sahih Contracts
/// @notice Deploys and tracks issuer token proxies
contract Factory is AccessControl {
    using PeriodLib for string;

    /// @notice Parameters for deploying a new issuer token
    struct CreateIssuerTokenParams {
        string issuerId;
        string tokenName;
        string tokenSymbol;
        uint256 totalSupply;
        uint256 pricePerUnit;
        uint256 profitSharingRatio;
        string distributionPeriod;
        bool transferRestricted;
        address issuerWallet;
    }

    /// @notice Metadata tracked for a deployed issuer contract
    struct IssuerMeta {
        string issuerId;
        uint256 deployedAt;
        bool active;
    }

    /// @notice Summary of an issuer used for listing
    struct IssuerSummary {
        string issuerId;
        address contractAddress;
    }

    /// @notice Role allowed to update the token implementation and roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role allowed to create new issuer tokens and update issuer status
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Maximum allowed profit sharing ratio, in basis points
    uint256 public constant MAX_PROFIT_SHARING_RATIO = 10_000;

    /// @notice Deployed issuer contract address for a given issuer ID
    mapping(string => address) public issuerContracts;
    /// @notice Metadata for a given deployed issuer contract address
    mapping(address => IssuerMeta) private issuerMeta;
    /// @notice All deployed issuer contract addresses, in deployment order
    address[] public allIssuerContracts;
    /// @notice Implementation address used when deploying new issuer token proxies
    address public tokenImplementation;
    /// @notice Address granted admin/default-admin roles on newly deployed issuer tokens
    address public tokenAdmin;
    /// @notice Address granted the operator role on newly deployed issuer tokens
    address public tokenOperator;

    /// @notice Emitted when a new issuer token is deployed
    /// @dev `issuerId` is emitted unindexed so indexers can read the raw string; filter on `issuerIdHash`
    /// @param issuerIdHash keccak256 hash of the issuer ID, for log filtering
    /// @param contractAddress Address of the deployed issuer token proxy
    /// @param issuerId Issuer ID the token was registered under
    /// @param timestamp Timestamp the issuer token was deployed
    event IssuerTokenCreated(
        bytes32 indexed issuerIdHash, address indexed contractAddress, string issuerId, uint256 timestamp
    );
    /// @notice Emitted when the token implementation address is updated
    /// @param tokenImplementation New implementation address
    event TokenImplementationUpdated(address indexed tokenImplementation);
    /// @notice Emitted when the token admin/operator roles are updated
    /// @param tokenAdmin New token admin address
    /// @param tokenOperator New token operator address
    event TokenRolesUpdated(address indexed tokenAdmin, address indexed tokenOperator);
    /// @notice Emitted when an issuer's active status is updated
    /// @dev `issuerId` is emitted unindexed so indexers can read the raw string; filter on `issuerIdHash`
    /// @param issuerIdHash keccak256 hash of the issuer ID, for log filtering
    /// @param contractAddress Deployed issuer token proxy address
    /// @param issuerId Issuer ID that was updated
    /// @param active New active status
    event IssuerStatusUpdated(
        bytes32 indexed issuerIdHash, address indexed contractAddress, string issuerId, bool active
    );

    error ZeroAddress();
    error EmptyIssuerId();
    error EmptyTokenName();
    error EmptyTokenSymbol();
    error IssuerAlreadyRegistered(string issuerId);
    error IssuerNotFound(string issuerId);
    error IssuerContractNotFound(address contractAddress);
    error InvalidProfitSharingRatio(uint256 ratio);
    error InvalidTotalSupply();
    error InvalidPricePerUnit();
    error InvalidPagination(uint256 page, uint256 limit);

    /// @notice Deploys the factory and grants initial roles
    /// @param tokenImplementation_ Implementation address used for new issuer token proxies
    /// @param admin Address granted the default admin and admin roles
    /// @param operator Address granted the operator role
    constructor(
        address tokenImplementation_,
        address admin,
        address operator
    ) {
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

    /// @notice Deploys a new issuer token proxy and registers it under the given issuer ID
    /// @param params Parameters describing the issuer token to deploy
    /// @return contractAddress Address of the newly deployed issuer token proxy
    /// @return deployedAt Timestamp the issuer token was deployed
    function createIssuerToken(
        CreateIssuerTokenParams calldata params
    ) external onlyRole(OPERATOR_ROLE) returns (address contractAddress, uint256 deployedAt) {
        _validateCreateIssuerTokenParams(params);

        contractAddress = _deployIssuerToken(params);
        deployedAt = block.timestamp;

        issuerContracts[params.issuerId] = contractAddress;
        issuerMeta[contractAddress] = IssuerMeta({ issuerId: params.issuerId, deployedAt: deployedAt, active: true });
        allIssuerContracts.push(contractAddress);

        emit IssuerTokenCreated(keccak256(bytes(params.issuerId)), contractAddress, params.issuerId, deployedAt);
    }

    /// @notice Updates the implementation address used for new issuer token proxies
    /// @param tokenImplementation_ New implementation address
    function setTokenImplementation(
        address tokenImplementation_
    ) external onlyRole(ADMIN_ROLE) {
        if (tokenImplementation_ == address(0)) {
            revert ZeroAddress();
        }
        tokenImplementation = tokenImplementation_;

        emit TokenImplementationUpdated(tokenImplementation_);
    }

    /// @notice Updates the admin and operator addresses granted on newly deployed issuer tokens
    /// @param tokenAdmin_ New token admin address
    /// @param tokenOperator_ New token operator address
    function setTokenRoles(
        address tokenAdmin_,
        address tokenOperator_
    ) external onlyRole(ADMIN_ROLE) {
        if (tokenAdmin_ == address(0) || tokenOperator_ == address(0)) {
            revert ZeroAddress();
        }
        tokenAdmin = tokenAdmin_;
        tokenOperator = tokenOperator_;

        emit TokenRolesUpdated(tokenAdmin_, tokenOperator_);
    }

    /// @notice Updates whether an issuer is active
    /// @dev Propagates the status to the issuer token itself, where it gates `purchaseTokens`
    /// @param issuerId Issuer ID to update
    /// @param active New active status
    function setIssuerStatus(
        string calldata issuerId,
        bool active
    ) external onlyRole(ADMIN_ROLE) {
        address contractAddress = issuerContracts[issuerId];
        if (contractAddress == address(0)) {
            revert IssuerNotFound(issuerId);
        }
        issuerMeta[contractAddress].active = active;
        IIssuerToken(contractAddress).setActive(active);

        emit IssuerStatusUpdated(keccak256(bytes(issuerId)), contractAddress, issuerId, active);
    }

    /// @notice Fetches deployment info for an issuer
    /// @param issuerId Issuer ID to query
    /// @return contractAddress Deployed issuer token proxy address
    /// @return deployedAt Timestamp the issuer token was deployed
    /// @return active Whether the issuer is currently active
    function getIssuerContract(
        string calldata issuerId
    ) external view returns (address contractAddress, uint256 deployedAt, bool active) {
        contractAddress = issuerContracts[issuerId];
        if (contractAddress == address(0)) {
            revert IssuerNotFound(issuerId);
        }

        IssuerMeta memory meta = issuerMeta[contractAddress];
        deployedAt = meta.deployedAt;
        active = meta.active;
    }

    /// @notice Fetches the metadata stored for a deployed issuer contract
    /// @dev Reverse lookup of `getIssuerContract`: distributions are recorded against a contract
    /// address while attestations are keyed by issuer ID, so callers need to resolve one to the other
    /// @param contractAddress Deployed issuer token proxy address to query
    /// @return The metadata registered for that contract
    function getIssuerMeta(
        address contractAddress
    ) external view returns (IssuerMeta memory) {
        IssuerMeta memory meta = issuerMeta[contractAddress];
        if (meta.deployedAt == 0) {
            revert IssuerContractNotFound(contractAddress);
        }
        return meta;
    }

    /// @notice Lists deployed issuers with pagination
    /// @param page 1-indexed page number to fetch
    /// @param limit Maximum number of issuers per page
    /// @return issuers Issuer summaries for the requested page
    /// @return totalCount Total number of deployed issuers
    function listAllIssuers(
        uint256 page,
        uint256 limit
    ) external view returns (IssuerSummary[] memory issuers, uint256 totalCount) {
        if (page == 0 || limit == 0) {
            revert InvalidPagination(page, limit);
        }

        totalCount = allIssuerContracts.length;
        uint256 start = (page - 1) * limit;
        if (!(start < totalCount)) {
            return (new IssuerSummary[](0), totalCount);
        }

        uint256 end = start + limit;
        if (end > totalCount) {
            end = totalCount;
        }

        issuers = new IssuerSummary[](end - start);
        for (uint256 i = start; i < end; ++i) {
            address contractAddress = allIssuerContracts[i];
            issuers[i - start] =
                IssuerSummary({ issuerId: issuerMeta[contractAddress].issuerId, contractAddress: contractAddress });
        }
    }

    /// @notice Returns the total number of deployed issuers
    /// @return Total number of deployed issuers
    function totalIssuers() external view returns (uint256) {
        return allIssuerContracts.length;
    }

    /// @notice Deploys and initializes a new issuer token proxy
    /// @param params Parameters describing the issuer token to deploy
    /// @return Address of the newly deployed issuer token proxy
    function _deployIssuerToken(
        CreateIssuerTokenParams calldata params
    ) private returns (address) {
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
            operator: tokenOperator,
            factory: address(this),
            issuerWallet: params.issuerWallet
        });

        bytes memory initData = abi.encodeCall(IIssuerToken.initialize, (initParams));
        return address(new ERC1967Proxy(tokenImplementation, initData));
    }

    /// @notice Validates parameters for deploying a new issuer token
    /// @param params Parameters describing the issuer token to deploy
    function _validateCreateIssuerTokenParams(
        CreateIssuerTokenParams calldata params
    ) private view {
        if (params.issuerId.isEmpty()) {
            revert EmptyIssuerId();
        }
        if (params.tokenName.isEmpty()) {
            revert EmptyTokenName();
        }
        if (params.tokenSymbol.isEmpty()) {
            revert EmptyTokenSymbol();
        }
        if (issuerContracts[params.issuerId] != address(0)) {
            revert IssuerAlreadyRegistered(params.issuerId);
        }
        if (params.issuerWallet == address(0)) {
            revert ZeroAddress();
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
    }
}
