// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice One-time Sepolia ETH settlement for HomeSpace membership orders.
/// @dev Backend signs EIP-712 PaymentQuote; domain binds chainId and this contract address.
contract EthPayment is Ownable2Step, EIP712, ReentrancyGuard {
    bytes32 public constant PAYMENT_QUOTE_TYPEHASH = keccak256(
        "PaymentQuote(bytes32 paymentId,address payer,address recipient,uint256 amountWei,uint256 expiresAt)"
    );

    /// @notice Backend address authorized to sign payment quotes.
    address public quoteSigner;

    /// @notice True after a successful payment for the given opaque payment id.
    mapping(bytes32 paymentId => bool paid) public paidPayments;

    error InvalidPaymentId();
    error InvalidRecipient();
    error InvalidAmount();
    error InvalidQuoteSigner();
    error WrongPayer(address expected, address actual);
    error WrongAmount(uint256 expected, uint256 actual);
    error QuoteExpired(uint256 expiresAt, uint256 timestamp);
    error InvalidSignature();
    error PaymentAlreadyPaid(bytes32 paymentId);
    error EthTransferFailed(address recipient, uint256 amount);

    event QuoteSignerUpdated(address indexed previousSigner, address indexed newSigner);
    event PaymentReceived(
        bytes32 indexed paymentId, address indexed payer, address indexed recipient, uint256 amountWei
    );

    /// @param initialOwner Admin that can rotate the quote signer.
    /// @param initialQuoteSigner Backend key that signs EIP-712 PaymentQuote payloads.
    constructor(address initialOwner, address initialQuoteSigner)
        Ownable(initialOwner)
        EIP712("HomeSpaceEthPayment", "1")
    {
        if (initialQuoteSigner == address(0)) revert InvalidQuoteSigner();
        quoteSigner = initialQuoteSigner;
    }

    /// @notice Rotate the backend signer; does not clear already-paid payment ids.
    function setQuoteSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidQuoteSigner();
        address previousSigner = quoteSigner;
        quoteSigner = newSigner;
        emit QuoteSignerUpdated(previousSigner, newSigner);
    }

    /// @notice EIP-712 digest the backend must sign for a one-time quote.
    function hashPaymentQuote(
        bytes32 paymentId,
        address payer,
        address recipient,
        uint256 amountWei,
        uint256 expiresAt
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(PAYMENT_QUOTE_TYPEHASH, paymentId, payer, recipient, amountWei, expiresAt))
        );
    }

    /// @notice Pay a signed membership quote by transferring exact ETH to the platform recipient.
    /// @param paymentId Opaque one-time payment id; replay is rejected after success.
    /// @param payer Address authorized to pay; must equal msg.sender.
    /// @param recipient Destination that receives amountWei.
    /// @param amountWei Exact wei value that must equal msg.value.
    /// @param expiresAt Inclusive unix-second deadline; later timestamps revert.
    /// @param signature 65-byte ECDSA signature over hashPaymentQuote(...) by quoteSigner.
    function pay(
        bytes32 paymentId,
        address payer,
        address recipient,
        uint256 amountWei,
        uint256 expiresAt,
        bytes calldata signature
    ) external payable nonReentrant {
        if (paymentId == bytes32(0)) revert InvalidPaymentId();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        if (amountWei == 0) revert InvalidAmount();
        if (msg.sender != payer) revert WrongPayer(payer, msg.sender);
        if (msg.value != amountWei) revert WrongAmount(amountWei, msg.value);
        if (block.timestamp > expiresAt) revert QuoteExpired(expiresAt, block.timestamp);
        if (paidPayments[paymentId]) revert PaymentAlreadyPaid(paymentId);

        bytes32 digest = hashPaymentQuote(paymentId, payer, recipient, amountWei, expiresAt);
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != quoteSigner) revert InvalidSignature();

        paidPayments[paymentId] = true;

        (bool success,) = recipient.call{value: amountWei}("");
        if (!success) revert EthTransferFailed(recipient, amountWei);

        emit PaymentReceived(paymentId, payer, recipient, amountWei);
    }
}
