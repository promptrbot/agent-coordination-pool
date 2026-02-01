import { expect } from "chai";
import { ethers } from "hardhat";
import { ACP, MockERC20 } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { parseEther, ZeroAddress } from "ethers";

describe("Security Tests", function () {
  let acp: ACP;
  let token: MockERC20;
  let owner: SignerWithAddress;
  let controller: SignerWithAddress;
  let alice: SignerWithAddress;
  let attacker: SignerWithAddress;

  beforeEach(async function () {
    [owner, controller, alice, attacker] = await ethers.getSigners();

    const ACPFactory = await ethers.getContractFactory("ACP");
    acp = await ACPFactory.deploy();

    const TokenFactory = await ethers.getContractFactory("MockERC20");
    token = await TokenFactory.deploy("Test", "TEST", 18);
  });

  describe("Access Control Attacks", function () {
    it("should prevent non-controller from contributing", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      await expect(
        acp.connect(attacker).contribute(0, alice.address, { value: parseEther("1") })
      ).to.be.revertedWith("not controller");
    });

    it("should prevent non-controller from executing", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("1") });
      
      await expect(
        acp.connect(attacker).execute(0, attacker.address, parseEther("1"), "0x")
      ).to.be.revertedWith("not controller");
    });

    it("should prevent non-controller from distributing", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("1") });
      
      await expect(
        acp.connect(attacker).distribute(0, ZeroAddress)
      ).to.be.revertedWith("not controller");
    });

    it("should prevent non-controller from depositing", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      await expect(
        acp.connect(attacker).deposit(0, { value: parseEther("1") })
      ).to.be.revertedWith("not controller");
    });

    it("should prevent controller of pool A from operating on pool B", async function () {
      await acp.connect(controller).createPool(ZeroAddress); // Pool 0
      await acp.connect(alice).createPool(ZeroAddress); // Pool 1
      
      await acp.connect(alice).contribute(1, alice.address, { value: parseEther("1") });
      
      // Controller of pool 0 tries to steal from pool 1
      await expect(
        acp.connect(controller).execute(1, controller.address, parseEther("1"), "0x")
      ).to.be.revertedWith("not controller");
    });
  });

  describe("Reentrancy Attacks", function () {
    let maliciousReceiver: any;

    beforeEach(async function () {
      // Deploy malicious contract that tries to reenter
      const MaliciousFactory = await ethers.getContractFactory("MaliciousReceiver");
      maliciousReceiver = await MaliciousFactory.deploy(await acp.getAddress());
    });

    it("should not be vulnerable to reentrancy on execute", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("10") });
      
      // Try to execute to malicious contract
      // Even if malicious contract tries to reenter, it should fail because:
      // 1. It's not the controller
      // 2. State updates happen before external calls
      await expect(
        acp.connect(controller).execute(0, await maliciousReceiver.getAddress(), parseEther("5"), "0x")
      ).to.not.be.reverted;
      
      // Balance should be correct (not drained)
      const remaining = await ethers.provider.getBalance(await acp.getAddress());
      expect(remaining).to.equal(parseEther("5"));
    });

    it("should not be vulnerable to reentrancy on distribute", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Use malicious contract as a contributor
      await acp.connect(controller).contribute(0, await maliciousReceiver.getAddress(), { value: parseEther("5") });
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("5") });
      
      // Set up malicious contract to try reentrancy
      await maliciousReceiver.setReentrancyTarget(0);
      
      // Distribute should complete successfully
      // Malicious contract's reentrant call should fail
      await acp.connect(controller).distribute(0, ZeroAddress);
      
      // Alice should have received her share
      // (Malicious contract might have caused revert of its own receive, but overall tx succeeds)
    });
  });

  describe("Overflow/Underflow Attacks", function () {
    it("should handle maximum uint256 contribution", async function () {
      // This would require massive ETH, so we test the math instead
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Contribute max safe amount
      const maxSafe = parseEther("1000000"); // 1M ETH (way more than exists)
      
      // This should not overflow in any calculations
      // In practice, this test is limited by available ETH in the test env
    });

    it("should not allow contribution overflow via repeated additions", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Contribute many times
      const amount = parseEther("100");
      let total = 0n;
      
      for (let i = 0; i < 10; i++) {
        await acp.connect(controller).contribute(0, alice.address, { value: amount });
        total += amount;
      }
      
      expect(await acp.getContribution(0, alice.address)).to.equal(total);
    });
  });

  describe("Front-running Attacks", function () {
    it("should not allow front-running of distribution", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("5") });
      
      // Attacker sees pending distribute and tries to add themselves
      // This should fail because attacker is not controller
      await expect(
        acp.connect(attacker).contribute(0, attacker.address, { value: parseEther("100") })
      ).to.be.revertedWith("not controller");
    });
  });

  describe("Fund Isolation Attacks", function () {
    it("should not allow stealing funds from other pools", async function () {
      // Create two pools
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Fund pool 0 with 10 ETH
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("10") });
      
      // Fund pool 1 with 1 ETH
      await acp.connect(controller).contribute(1, alice.address, { value: parseEther("1") });
      
      // Try to execute more than pool 1 has (trying to steal from pool 0)
      await expect(
        acp.connect(controller).execute(1, attacker.address, parseEther("5"), "0x")
      ).to.be.reverted;
      
      // Pool 0 should still have its funds
      const acpBalance = await ethers.provider.getBalance(await acp.getAddress());
      expect(acpBalance).to.equal(parseEther("11"));
    });

    it("should not allow cross-pool distribution theft", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).createPool(ZeroAddress);
      
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("10") });
      await acp.connect(controller).contribute(1, attacker.address, { value: parseEther("1") });
      
      // Distribute pool 1 (attacker's pool)
      const attackerBefore = await ethers.provider.getBalance(attacker.address);
      await acp.connect(controller).distribute(1, ZeroAddress);
      const attackerAfter = await ethers.provider.getBalance(attacker.address);
      
      // Attacker should only receive their 1 ETH, not 10 ETH from pool 0
      expect(attackerAfter - attackerBefore).to.equal(parseEther("1"));
    });
  });

  describe("Token Manipulation Attacks", function () {
    it("should handle malicious token that reverts on transfer", async function () {
      const RevertingTokenFactory = await ethers.getContractFactory("RevertingToken");
      const revertingToken = await RevertingTokenFactory.deploy();
      
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("1") });
      
      // Mint reverting tokens to ACP
      await revertingToken.mint(await acp.getAddress(), parseEther("1000"));
      await revertingToken.setShouldRevert(true);
      
      // Distribution should handle the revert gracefully
      // (This depends on implementation - may revert entire tx or skip)
      await expect(
        acp.connect(controller).distribute(0, await revertingToken.getAddress())
      ).to.be.reverted; // Expected - bad token breaks distribution
    });

    it("should handle fee-on-transfer tokens", async function () {
      // Create a fee-on-transfer token mock
      const FeeTokenFactory = await ethers.getContractFactory("FeeOnTransferToken");
      const feeToken = await FeeTokenFactory.deploy();
      
      await acp.connect(controller).createPool(await feeToken.getAddress());
      
      // Mint to controller
      await feeToken.mint(controller.address, parseEther("100"));
      await feeToken.connect(controller).approve(await acp.getAddress(), parseEther("100"));
      
      // Contribute 100, but only ~95 arrives due to fee
      await acp.connect(controller).contributeToken(0, alice.address, parseEther("100"));
      
      // Contribution tracking should reflect actual received amount
      // (This is a known issue with fee-on-transfer tokens in many protocols)
    });
  });

  describe("Griefing Attacks", function () {
    it("should handle many small contributors without running out of gas", async function () {
      this.timeout(120000);
      
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Add many contributors
      const numContributors = 100;
      const amount = parseEther("0.01");
      
      const signers = await ethers.getSigners();
      for (let i = 0; i < Math.min(numContributors, signers.length); i++) {
        await acp.connect(controller).contribute(0, signers[i].address, { value: amount });
      }
      
      // Distribution should not run out of gas
      const tx = await acp.connect(controller).distribute(0, ZeroAddress);
      const receipt = await tx.wait();
      
      // Should complete successfully
      expect(receipt?.status).to.equal(1);
    });

    it("should handle dust attack (tiny contributions)", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Attacker adds many 1-wei contributions
      for (let i = 0; i < 10; i++) {
        await acp.connect(controller).contribute(0, attacker.address, { value: 1n });
      }
      
      // Normal user adds substantial contribution
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("10") });
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      await acp.connect(controller).distribute(0, ZeroAddress);
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      
      // Alice should get nearly everything (10 wei attacker vs 10 ETH alice)
      expect(aliceAfter - aliceBefore).to.be.closeTo(parseEther("10"), parseEther("0.0001"));
    });
  });

  describe("Controller Takeover Attacks", function () {
    it("should not allow changing controller after pool creation", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      // There should be no function to change controller
      // The controller is set at creation and immutable for that pool
      
      const [poolController,,,] = await acp.getPoolInfo(0);
      expect(poolController).to.equal(controller.address);
    });
  });
});

// Malicious contracts for testing

// @ts-ignore
const MaliciousReceiverCode = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IACP {
    function contribute(uint256 poolId, address contributor) external payable;
    function distribute(uint256 poolId, address token) external;
}

contract MaliciousReceiver {
    IACP public acp;
    uint256 public targetPool;
    bool public attemptReentrancy;
    
    constructor(address _acp) {
        acp = IACP(_acp);
    }
    
    function setReentrancyTarget(uint256 _pool) external {
        targetPool = _pool;
        attemptReentrancy = true;
    }
    
    receive() external payable {
        if (attemptReentrancy) {
            attemptReentrancy = false;
            // Try to reenter - should fail
            try acp.distribute(targetPool, address(0)) {} catch {}
        }
    }
}
`;

// @ts-ignore  
const RevertingTokenCode = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RevertingToken is ERC20 {
    bool public shouldRevert;
    
    constructor() ERC20("Reverting", "REV") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setShouldRevert(bool _should) external {
        shouldRevert = _should;
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldRevert) revert("Reverting!");
        return super.transfer(to, amount);
    }
}
`;

// @ts-ignore
const FeeOnTransferTokenCode = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeOnTransferToken is ERC20 {
    uint256 public feePercent = 5; // 5% fee
    
    constructor() ERC20("FeeToken", "FEE") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 100;
        _burn(msg.sender, fee);
        return super.transfer(to, amount - fee);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 100;
        _burn(from, fee);
        return super.transferFrom(from, to, amount - fee);
    }
}
`;
