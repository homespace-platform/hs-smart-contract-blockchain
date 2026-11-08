// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ContractDocumentRegistry} from "../src/ContractDocumentRegistry.sol";

// Script chạy bằng Forge trên máy, không phải registry lưu proof sau deploy.
// Flow forge create trong DEPLOY.md tạo registry trực tiếp, không gọi run() ở đây.
contract DeployContractDocumentRegistry is Script {
    error UnsupportedChain(uint256 chainId);

    /// @notice Điểm vào khi dùng forge script; trả về registry vừa tạo trong lần chạy này.
    function run() external returns (ContractDocumentRegistry registry) {
        // Chỉ cho local Anvil (31337) hoặc Ethereum Sepolia (11155111), chặn nhầm mainnet.
        if (block.chainid != 31337 && block.chainid != 11155111) revert UnsupportedChain(block.chainid);
        // Địa chỉ public được PowerShell lấy từ keystore ACCOUNT, không phải private key.
        address initialOwner = vm.envAddress("REGISTRY_OWNER");

        // Ghi nhận các lời gọi tạo contract để Forge mô phỏng hoặc gửi bằng signer từ CLI.
        // Chỉ thêm --broadcast khi bạn chủ động muốn gửi transaction lên mạng.
        vm.startBroadcast();
        // Chạy constructor(initialOwner): đặt owner, chưa gọi registerDocument().
        registry = new ContractDocumentRegistry(initialOwner);
        vm.stopBroadcast();
    }
}
