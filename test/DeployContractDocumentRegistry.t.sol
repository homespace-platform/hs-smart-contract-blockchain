// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployContractDocumentRegistry} from "../script/DeployContractDocumentRegistry.s.sol";
import {ContractDocumentRegistry} from "../src/ContractDocumentRegistry.sol";

contract DeployContractDocumentRegistryTest is Test {
    DeployContractDocumentRegistry private deployer;
    address private owner;

    function setUp() public {
        owner = makeAddr("registry-owner");
        vm.setEnv("REGISTRY_OWNER", vm.toString(owner));
        deployer = new DeployContractDocumentRegistry();
    }

    function test_DeploysLocallyWithConfiguredOwner() public {
        vm.chainId(31337);
        ContractDocumentRegistry registry = deployer.run();
        assertEq(registry.owner(), owner);
    }

    function test_DeploysOnSepoliaWithConfiguredOwner() public {
        vm.chainId(11155111);
        ContractDocumentRegistry registry = deployer.run();
        assertEq(registry.owner(), owner);
    }

    function test_RejectsMainnet() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeployContractDocumentRegistry.UnsupportedChain.selector, 1));
        deployer.run();
    }
}
