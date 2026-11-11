// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EthPayment} from "../src/EthPayment.sol";

contract EthPaymentTest is Test {
    EthPayment private payment;
    uint256 private signerKey;
    address private signer;
    address private owner;
    address private payer;
    address private recipient;
    address private stranger;

    bytes32 private constant PAYMENT_ID = keccak256("payment-1");
    uint256 private constant AMOUNT = 0.05 ether;
    uint256 private expiresAt;

    event PaymentReceived(
        bytes32 indexed paymentId, address indexed payer, address indexed recipient, uint256 amountWei
    );

    function setUp() public {
        owner = makeAddr("owner");
        payer = makeAddr("payer");
        recipient = makeAddr("recipient");
        stranger = makeAddr("stranger");
        signerKey = uint256(keccak256("quote-signer"));
        signer = vm.addr(signerKey);
        payment = new EthPayment(owner, signer);
        expiresAt = block.timestamp + 1 hours;
        vm.deal(payer, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    function test_ConstructorSetsOwnerAndSigner() public view {
        assertEq(payment.owner(), owner);
        assertEq(payment.quoteSigner(), signer);
    }

    function test_RevertsForZeroOwnerOrSigner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new EthPayment(address(0), signer);
        vm.expectRevert(EthPayment.InvalidQuoteSigner.selector);
        new EthPayment(owner, address(0));
    }

    function test_PayTransfersEthAndEmitsPaymentReceived() public {
        bytes memory signature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);

        vm.expectEmit(true, true, true, true, address(payment));
        emit PaymentReceived(PAYMENT_ID, payer, recipient, AMOUNT);

        uint256 recipientBefore = recipient.balance;
        vm.prank(payer);
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, signature);

        assertTrue(payment.paidPayments(PAYMENT_ID));
        assertEq(recipient.balance, recipientBefore + AMOUNT);
        assertEq(address(payment).balance, 0);
    }

    function test_RevertsWrongPayer() public {
        bytes memory signature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(EthPayment.WrongPayer.selector, payer, stranger));
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, signature);
    }

    function test_RevertsWrongAmount() public {
        bytes memory signature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(EthPayment.WrongAmount.selector, AMOUNT, AMOUNT + 1));
        payment.pay{value: AMOUNT + 1}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, signature);
    }

    function test_RevertsExpiredQuote() public {
        bytes memory signature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);
        vm.warp(expiresAt + 1);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(EthPayment.QuoteExpired.selector, expiresAt, expiresAt + 1));
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, signature);
    }

    function test_RevertsInvalidSignature() public {
        bytes memory badSignature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt + 1);
        vm.prank(payer);
        vm.expectRevert(EthPayment.InvalidSignature.selector);
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, badSignature);
    }

    function test_RevertsReplay() public {
        bytes memory signature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);
        vm.prank(payer);
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, signature);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(EthPayment.PaymentAlreadyPaid.selector, PAYMENT_ID));
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, signature);
    }

    function test_RevertsFailedRecipientTransferAndLeavesUnpaid() public {
        RevertingRecipient rejectingRecipient = new RevertingRecipient();
        bytes memory signature =
            _signQuote(PAYMENT_ID, payer, address(rejectingRecipient), AMOUNT, expiresAt);
        uint256 payerBefore = payer.balance;

        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSelector(
                EthPayment.EthTransferFailed.selector, address(rejectingRecipient), AMOUNT
            )
        );
        payment.pay{value: AMOUNT}(
            PAYMENT_ID, payer, address(rejectingRecipient), AMOUNT, expiresAt, signature
        );

        assertFalse(payment.paidPayments(PAYMENT_ID));
        assertEq(payer.balance, payerBefore);
        assertEq(address(payment).balance, 0);
        assertEq(address(rejectingRecipient).balance, 0);
    }

    function test_OwnerCanRotateQuoteSigner() public {
        uint256 newKey = uint256(keccak256("new-signer"));
        address newSigner = vm.addr(newKey);
        vm.prank(owner);
        payment.setQuoteSigner(newSigner);
        assertEq(payment.quoteSigner(), newSigner);

        bytes memory oldSignature = _signQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);
        vm.prank(payer);
        vm.expectRevert(EthPayment.InvalidSignature.selector);
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, oldSignature);

        bytes32 digest = payment.hashPaymentQuote(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newKey, digest);
        bytes memory newSignature = abi.encodePacked(r, s, v);
        vm.prank(payer);
        payment.pay{value: AMOUNT}(PAYMENT_ID, payer, recipient, AMOUNT, expiresAt, newSignature);
        assertTrue(payment.paidPayments(PAYMENT_ID));
    }

    function _signQuote(
        bytes32 paymentId,
        address quotePayer,
        address quoteRecipient,
        uint256 amountWei,
        uint256 quoteExpiresAt
    ) private view returns (bytes memory) {
        bytes32 digest = payment.hashPaymentQuote(paymentId, quotePayer, quoteRecipient, amountWei, quoteExpiresAt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

contract RevertingRecipient {
    receive() external payable {
        revert("reject-eth");
    }
}
