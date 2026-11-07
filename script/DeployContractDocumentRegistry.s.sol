// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ContractDocumentRegistry} from "../src/ContractDocumentRegistry.sol";

contract DeployContractDocumentRegistry is Script {
    error UnsupportedChain(uint256 chainId);

    function run() external returns (ContractDocumentRegistry registry) {
        if (block.chainid != 31337 && block.chainid != 11155111) revert UnsupportedChain(block.chainid);
        address initialOwner = vm.envAddress("REGISTRY_OWNER");

        vm.startBroadcast();
        registry = new ContractDocumentRegistry(initialOwner);
        vm.stopBroadcast();
    }
}
