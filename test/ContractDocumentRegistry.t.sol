// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ContractDocumentRegistry} from "../src/ContractDocumentRegistry.sol";

contract ContractDocumentRegistryTest is Test {
    ContractDocumentRegistry private registry;
    address private owner;
    address private stranger;
    bytes32 private constant DOCUMENT_ID = keccak256("opaque-document-1");
    bytes32 private expectedHash;

    event DocumentRegistered(
        bytes32 indexed documentId, bytes32 indexed documentHash, address indexed recorder, uint256 registeredAt
    );

    function setUp() public {
        expectedHash = sha256("exact-signed-pdf-bytes");
        owner = makeAddr("owner");
        stranger = makeAddr("stranger");
        registry = new ContractDocumentRegistry(owner);
    }

    function test_ConstructorSetsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_RevertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ContractDocumentRegistry(address(0));
    }

    function test_RegistersHashAndRecordingTimeAndEmitsEvent() public {
        vm.warp(1_800_000_000);
        vm.expectEmit(true, true, true, true, address(registry));
        emit DocumentRegistered(DOCUMENT_ID, expectedHash, owner, block.timestamp);

        vm.prank(owner);
        registry.registerDocument(DOCUMENT_ID, expectedHash);

        (bytes32 storedHash, uint256 registeredAt) = registry.documents(DOCUMENT_ID);
        assertEq(storedHash, expectedHash);
        assertEq(registeredAt, block.timestamp);
        assertTrue(registry.verifyDocument(DOCUMENT_ID, expectedHash));
    }

    function test_RevertsForUnauthorizedWriter() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.registerDocument(DOCUMENT_ID, expectedHash);
    }

    function test_RevertsForZeroDocumentId() public {
        vm.prank(owner);
        vm.expectRevert(ContractDocumentRegistry.InvalidDocumentId.selector);
        registry.registerDocument(bytes32(0), expectedHash);
    }

    function test_RevertsForZeroDocumentHash() public {
        vm.prank(owner);
        vm.expectRevert(ContractDocumentRegistry.InvalidDocumentHash.selector);
        registry.registerDocument(DOCUMENT_ID, bytes32(0));
    }

    function test_UnknownDocumentNeverVerifiesIncludingZeroHash() public view {
        assertFalse(registry.verifyDocument(DOCUMENT_ID, expectedHash));
        assertFalse(registry.verifyDocument(DOCUMENT_ID, bytes32(0)));
        assertFalse(registry.verifyDocument(bytes32(0), bytes32(0)));
    }

    function test_AlteredHashDoesNotVerify() public {
        vm.prank(owner);
        registry.registerDocument(DOCUMENT_ID, expectedHash);
        assertFalse(registry.verifyDocument(DOCUMENT_ID, sha256("altered-pdf-bytes")));
        assertFalse(registry.verifyDocument(DOCUMENT_ID, bytes32(0)));
    }

    function test_DuplicateSubmissionReverts() public {
        vm.startPrank(owner);
        registry.registerDocument(DOCUMENT_ID, expectedHash);
        vm.expectRevert(
            abi.encodeWithSelector(ContractDocumentRegistry.DocumentAlreadyRegistered.selector, DOCUMENT_ID)
        );
        registry.registerDocument(DOCUMENT_ID, expectedHash);
        vm.stopPrank();
    }

    function test_DifferentDocumentsKeepSeparateProofs() public {
        bytes32 secondId = keccak256("opaque-document-2");
        bytes32 secondHash = sha256("signed-appendix-pdf");
        vm.startPrank(owner);
        registry.registerDocument(DOCUMENT_ID, expectedHash);
        registry.registerDocument(secondId, secondHash);
        vm.stopPrank();

        assertTrue(registry.verifyDocument(DOCUMENT_ID, expectedHash));
        assertTrue(registry.verifyDocument(secondId, secondHash));
        assertFalse(registry.verifyDocument(secondId, expectedHash));
    }

    function test_OwnershipTransferRequiresAcceptanceAndKeepsProofs() public {
        vm.startPrank(owner);
        registry.registerDocument(DOCUMENT_ID, expectedHash);
        registry.transferOwnership(stranger);
        vm.stopPrank();

        assertEq(registry.owner(), owner);
        assertEq(registry.pendingOwner(), stranger);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.registerDocument(keccak256("before-acceptance"), expectedHash);

        vm.prank(stranger);
        registry.acceptOwnership();
        assertEq(registry.owner(), stranger);
        assertEq(registry.pendingOwner(), address(0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        registry.registerDocument(keccak256("old-owner-write"), expectedHash);
        vm.prank(stranger);
        registry.registerDocument(keccak256("new-owner-write"), expectedHash);
        assertTrue(registry.verifyDocument(DOCUMENT_ID, expectedHash));
        assertTrue(registry.verifyDocument(keccak256("new-owner-write"), expectedHash));
    }

    function test_RevertsWhenSentEther() public {
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        (bool success,) = address(registry).call{value: 1 wei}(
            abi.encodeCall(ContractDocumentRegistry.registerDocument, (DOCUMENT_ID, expectedHash))
        );
        assertFalse(success);
        assertEq(address(registry).balance, 0);
        assertFalse(registry.verifyDocument(DOCUMENT_ID, expectedHash));
    }

    function testFuzz_RegisterAndVerify(bytes32 documentId, bytes32 documentHash, uint64 recordedAt) public {
        vm.assume(documentId != bytes32(0) && documentHash != bytes32(0));
        vm.warp(recordedAt);
        vm.prank(owner);
        registry.registerDocument(documentId, documentHash);

        (bytes32 storedHash, uint256 timestamp) = registry.documents(documentId);
        assertEq(storedHash, documentHash);
        assertEq(timestamp, recordedAt);
        assertTrue(registry.verifyDocument(documentId, documentHash));
    }

    function testFuzz_CannotOverwriteProof(bytes32 replacementHash) public {
        vm.assume(replacementHash != bytes32(0));
        vm.warp(100);
        vm.startPrank(owner);
        registry.registerDocument(DOCUMENT_ID, expectedHash);
        vm.warp(200);
        vm.expectRevert(
            abi.encodeWithSelector(ContractDocumentRegistry.DocumentAlreadyRegistered.selector, DOCUMENT_ID)
        );
        registry.registerDocument(DOCUMENT_ID, replacementHash);
        vm.stopPrank();

        (bytes32 storedHash, uint256 timestamp) = registry.documents(DOCUMENT_ID);
        assertEq(storedHash, expectedHash);
        assertEq(timestamp, 100);
    }
}
