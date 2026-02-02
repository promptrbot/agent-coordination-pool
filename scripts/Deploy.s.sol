// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/ACP.sol";

/**
 * @title Deploy
 * @notice Foundry deployment script for ACP on Base mainnet
 *
 * USAGE:
 *   forge script scripts/Deploy.s.sol:Deploy --rpc-url $BASE_RPC_URL --broadcast --verify
 *
 * REQUIRES:
 *   - PRIVATE_KEY env var (deployer wallet)
 *   - BASE_RPC_URL env var (Base mainnet RPC)
 *   - BASESCAN_API_KEY env var (for verification)
 */
contract Deploy is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ACP core primitive
        ACP acp = new ACP();

        console.log("ACP deployed at:", address(acp));

        vm.stopBroadcast();

        // Output for integration
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("ACP:", address(acp));
        console.log("\nNext steps:");
        console.log("1. Update README.md with deployed address");
        console.log("2. Create first test pool");
        console.log("3. Document gas costs");
        console.log("4. Share integration guide (AGENTS.md)");
    }
}
