// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/ACP.sol";
import "../use-cases/nft-flip/NFTFlip.sol";
import "../use-cases/alpha/Alpha.sol";
import "../use-cases/launchpad/Launchpad.sol";

/**
 * @title Deploy
 * @notice Foundry deployment script for ACP + all wrappers on Base mainnet
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

        console.log("=== ACP DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ACP core primitive
        ACP acp = new ACP();
        console.log("ACP deployed at:", address(acp));

        // Deploy NFTFlip wrapper
        NFTFlip nftFlip = new NFTFlip(address(acp));
        console.log("NFTFlip deployed at:", address(nftFlip));

        // Deploy Alpha wrapper
        Alpha alpha = new Alpha(address(acp));
        console.log("Alpha deployed at:", address(alpha));

        // Deploy Launchpad wrapper
        Launchpad launchpad = new Launchpad(address(acp));
        console.log("Launchpad deployed at:", address(launchpad));

        vm.stopBroadcast();

        // Output for integration
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("ACP:", address(acp));
        console.log("NFTFlip:", address(nftFlip));
        console.log("Alpha:", address(alpha));
        console.log("Launchpad:", address(launchpad));
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on BaseScan");
        console.log("2. Update README.md with deployed addresses");
        console.log("3. Create first test pool");
        console.log("4. Document gas costs");
        console.log("5. Share integration guide (AGENTS.md)");
    }
}
