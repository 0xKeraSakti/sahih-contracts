// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IEAS, AttestationRequest, EASAttestation } from "../../src/interfaces/IEAS.sol";

contract MockEAS is IEAS {
    uint256 public nonce;
    mapping(bytes32 => EASAttestation) private attestations;

    function attest(AttestationRequest calldata request) external payable returns (bytes32) {
        nonce++;
        bytes32 uid = keccak256(abi.encode(request.schema, request.data.data, msg.sender, nonce));

        attestations[uid] = EASAttestation({
            uid: uid,
            schema: request.schema,
            time: uint64(block.timestamp),
            expirationTime: request.data.expirationTime,
            revocationTime: 0,
            refUID: request.data.refUID,
            recipient: request.data.recipient,
            attester: msg.sender,
            revocable: request.data.revocable,
            data: request.data.data
        });

        return uid;
    }

    function getAttestation(bytes32 uid) external view returns (EASAttestation memory) {
        return attestations[uid];
    }
}
