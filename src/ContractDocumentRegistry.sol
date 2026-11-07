// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Immutable commitments to signed PDF files; the owner supplies their SHA-256 hashes.
contract ContractDocumentRegistry is Ownable2Step {
    struct DocumentProof {
        bytes32 documentHash;
        uint256 registeredAt;
    }

    error InvalidDocumentId();
    error InvalidDocumentHash();
    error DocumentAlreadyRegistered(bytes32 documentId);

    event DocumentRegistered(
        bytes32 indexed documentId, bytes32 indexed documentHash, address indexed recorder, uint256 registeredAt
    );

    mapping(bytes32 documentId => DocumentProof proof) public documents;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @param documentId Opaque file identity; use a new ID for each signed document or revision.
    /// @param documentHash SHA-256 of the exact final PDF bytes, computed off-chain.
    function registerDocument(bytes32 documentId, bytes32 documentHash) external onlyOwner {
        if (documentId == bytes32(0)) revert InvalidDocumentId();
        if (documentHash == bytes32(0)) revert InvalidDocumentHash();
        if (documents[documentId].documentHash != bytes32(0)) revert DocumentAlreadyRegistered(documentId);

        documents[documentId] = DocumentProof(documentHash, block.timestamp);
        emit DocumentRegistered(documentId, documentHash, msg.sender, block.timestamp);
    }

    function verifyDocument(bytes32 documentId, bytes32 documentHash) external view returns (bool) {
        bytes32 storedHash = documents[documentId].documentHash;
        return storedHash != bytes32(0) && storedHash == documentHash;
    }
}
