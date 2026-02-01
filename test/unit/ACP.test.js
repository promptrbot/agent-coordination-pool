const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseEther, ZeroAddress } = require("ethers");

describe("ACP", function () {
  let acp;
  let token;
  let owner;
  let controller;
  let alice;
  let bob;
  let charlie;
  let attacker;

  beforeEach(async function () {
    [owner, controller, alice, bob, charlie, attacker] = await ethers.getSigners();

    const ACPFactory = await ethers.getContractFactory("ACP");
    acp = await ACPFactory.deploy();

    const TokenFactory = await ethers.getContractFactory("MockERC20");
    token = await TokenFactory.deploy("Test Token", "TEST", 18);
  });

  describe("Pool Creation", function () {
    it("should create pool with ETH (address(0))", async function () {
      const tx = await acp.connect(controller).createPool(ZeroAddress);
      const receipt = await tx.wait();
      
      const poolId = 0;
      const [poolToken, poolController, totalContributed, contributorCount] = 
        await acp.getPoolInfo(poolId);
      
      expect(poolController).to.equal(controller.address);
      expect(poolToken).to.equal(ZeroAddress);
      expect(totalContributed).to.equal(0);
      expect(contributorCount).to.equal(0);
    });

    it("should create pool with ERC20 token", async function () {
      await acp.connect(controller).createPool(await token.getAddress());
      
      const [poolToken,,, ] = await acp.getPoolInfo(0);
      expect(poolToken).to.equal(await token.getAddress());
    });

    it("should emit PoolCreated event", async function () {
      await expect(acp.connect(controller).createPool(ZeroAddress))
        .to.emit(acp, "PoolCreated")
        .withArgs(0, controller.address, ZeroAddress);
    });

    it("should increment pool IDs", async function () {
      await acp.createPool(ZeroAddress);
      await acp.createPool(ZeroAddress);
      await acp.createPool(ZeroAddress);
      
      expect(await acp.poolCount()).to.equal(3);
    });
  });

  describe("ETH Contributions", function () {
    let poolId;

    beforeEach(async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      poolId = 0;
    });

    it("should accept ETH contributions", async function () {
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      
      expect(await acp.getContribution(poolId, alice.address)).to.equal(parseEther("1"));
    });

    it("should track multiple contributors", async function () {
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      await acp.connect(controller).contribute(poolId, bob.address, { value: parseEther("2") });
      await acp.connect(controller).contribute(poolId, charlie.address, { value: parseEther("0.5") });
      
      const [,,totalContributed, contributorCount] = await acp.getPoolInfo(poolId);
      
      expect(totalContributed).to.equal(parseEther("3.5"));
      expect(contributorCount).to.equal(3);
    });

    it("should accumulate contributions from same address", async function () {
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("2") });
      
      expect(await acp.getContribution(poolId, alice.address)).to.equal(parseEther("3"));
      
      const [,,,contributorCount] = await acp.getPoolInfo(poolId);
      expect(contributorCount).to.equal(1); // Same contributor, count = 1
    });

    it("should update pool balance", async function () {
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("5") });
      
      const [,,totalContributed,] = await acp.getPoolInfo(poolId);
      expect(totalContributed).to.equal(parseEther("5"));
    });

    it("should emit Contributed event", async function () {
      await expect(acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") }))
        .to.emit(acp, "Contributed")
        .withArgs(poolId, alice.address, parseEther("1"));
    });

    it("should revert with zero value", async function () {
      await expect(
        acp.connect(controller).contribute(poolId, alice.address, { value: 0 })
      ).to.be.revertedWith("no value");
    });

    it("should only allow controller to contribute", async function () {
      await expect(
        acp.connect(attacker).contribute(poolId, alice.address, { value: parseEther("1") })
      ).to.be.revertedWithCustomError(acp, "NotController");
    });
  });

  describe("ERC20 Contributions", function () {
    let poolId;

    beforeEach(async function () {
      await acp.connect(controller).createPool(await token.getAddress());
      poolId = 0;
      
      // Mint tokens to controller for contributions
      await token.mint(controller.address, parseEther("1000"));
      await token.connect(controller).approve(await acp.getAddress(), parseEther("1000"));
    });

    it("should accept ERC20 contributions", async function () {
      await acp.connect(controller).contributeToken(poolId, alice.address, parseEther("100"));
      
      expect(await acp.getContribution(poolId, alice.address)).to.equal(parseEther("100"));
    });

    it("should transfer tokens to ACP", async function () {
      const acpAddress = await acp.getAddress();
      const balanceBefore = await token.balanceOf(acpAddress);
      
      await acp.connect(controller).contributeToken(poolId, alice.address, parseEther("100"));
      
      const balanceAfter = await token.balanceOf(acpAddress);
      expect(balanceAfter - balanceBefore).to.equal(parseEther("100"));
    });

    it("should revert ERC20 contribution to ETH pool", async function () {
      await acp.connect(controller).createPool(ZeroAddress); // ETH pool
      
      await expect(
        acp.connect(controller).contributeToken(1, alice.address, parseEther("100"))
      ).to.be.revertedWith("not token pool");
    });

    it("should revert ETH contribution to token pool", async function () {
      await expect(
        acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") })
      ).to.be.revertedWith("not ETH pool");
    });
  });

  describe("Execute", function () {
    let poolId;

    beforeEach(async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      poolId = 0;
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("5") });
    });

    it("should transfer ETH to target", async function () {
      const balanceBefore = await ethers.provider.getBalance(bob.address);
      
      await acp.connect(controller).execute(poolId, bob.address, parseEther("3"), "0x");
      
      const balanceAfter = await ethers.provider.getBalance(bob.address);
      expect(balanceAfter - balanceBefore).to.equal(parseEther("3"));
    });

    it("should update pool balance after execute", async function () {
      await acp.connect(controller).execute(poolId, bob.address, parseEther("3"), "0x");
      
      // Balance tracking is internal, check via contract balance
      expect(await ethers.provider.getBalance(await acp.getAddress())).to.equal(parseEther("2"));
    });

    it("should revert if not controller", async function () {
      await expect(
        acp.connect(attacker).execute(poolId, bob.address, parseEther("1"), "0x")
      ).to.be.revertedWithCustomError(acp, "NotController");
    });

    it("should emit Executed event", async function () {
      await expect(acp.connect(controller).execute(poolId, bob.address, parseEther("1"), "0x"))
        .to.emit(acp, "Executed")
        .withArgs(poolId, bob.address, parseEther("1"), true);
    });
  });

  describe("Deposit", function () {
    let poolId;

    beforeEach(async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      poolId = 0;
    });

    it("should accept ETH deposits", async function () {
      await acp.connect(controller).deposit(poolId, { value: parseEther("10") });
      
      expect(await ethers.provider.getBalance(await acp.getAddress())).to.equal(parseEther("10"));
    });

    it("should only allow controller to deposit", async function () {
      await expect(
        acp.connect(attacker).deposit(poolId, { value: parseEther("1") })
      ).to.be.revertedWithCustomError(acp, "NotController");
    });
  });

  describe("Distribute ETH", function () {
    let poolId;

    beforeEach(async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      poolId = 0;
    });

    it("should distribute ETH pro-rata", async function () {
      // Alice: 1 ETH (20%), Bob: 4 ETH (80%)
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      await acp.connect(controller).contribute(poolId, bob.address, { value: parseEther("4") });
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      
      // Distribute the 5 ETH
      await acp.connect(controller).distribute(poolId, ZeroAddress);
      
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      
      expect(aliceAfter - aliceBefore).to.equal(parseEther("1"));
      expect(bobAfter - bobBefore).to.equal(parseEther("4"));
    });

    it("should distribute profits pro-rata", async function () {
      // Contribute 5 ETH, deposit 10 ETH (profit scenario)
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      await acp.connect(controller).contribute(poolId, bob.address, { value: parseEther("4") });
      
      // Simulate: execute all, then deposit double back
      await acp.connect(controller).execute(poolId, controller.address, parseEther("5"), "0x");
      await acp.connect(controller).deposit(poolId, { value: parseEther("10") });
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      
      await acp.connect(controller).distribute(poolId, ZeroAddress);
      
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      
      // Alice: 20% of 10 = 2 ETH, Bob: 80% of 10 = 8 ETH
      expect(aliceAfter - aliceBefore).to.equal(parseEther("2"));
      expect(bobAfter - bobBefore).to.equal(parseEther("8"));
    });

    it("should handle many contributors", async function () {
      const signers = await ethers.getSigners();
      const contributors = signers.slice(3, 13); // 10 contributors
      
      // Each contributes 1 ETH
      for (const c of contributors) {
        await acp.connect(controller).contribute(poolId, c.address, { value: parseEther("1") });
      }
      
      const balancesBefore = await Promise.all(
        contributors.map(c => ethers.provider.getBalance(c.address))
      );
      
      await acp.connect(controller).distribute(poolId, ZeroAddress);
      
      const balancesAfter = await Promise.all(
        contributors.map(c => ethers.provider.getBalance(c.address))
      );
      
      // Each should receive 1 ETH
      for (let i = 0; i < contributors.length; i++) {
        expect(balancesAfter[i] - balancesBefore[i]).to.equal(parseEther("1"));
      }
    });

    it("should only allow controller to distribute", async function () {
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      
      await expect(
        acp.connect(attacker).distribute(poolId, ZeroAddress)
      ).to.be.revertedWithCustomError(acp, "NotController");
    });
  });

  describe("Distribute ERC20", function () {
    let poolId;

    beforeEach(async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      poolId = 0;
      
      // Contribute ETH
      await acp.connect(controller).contribute(poolId, alice.address, { value: parseEther("1") });
      await acp.connect(controller).contribute(poolId, bob.address, { value: parseEther("4") });
    });

    it("should distribute ERC20 tokens pro-rata", async function () {
      // Mint tokens to ACP (simulating received tokens)
      await token.mint(await acp.getAddress(), parseEther("1000"));
      
      await acp.connect(controller).distribute(poolId, await token.getAddress());
      
      // Alice: 20% = 200, Bob: 80% = 800
      expect(await token.balanceOf(alice.address)).to.equal(parseEther("200"));
      expect(await token.balanceOf(bob.address)).to.equal(parseEther("800"));
    });
  });

  describe("Edge Cases", function () {
    it("should handle single contributor", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("5") });
      
      const balanceBefore = await ethers.provider.getBalance(alice.address);
      await acp.connect(controller).distribute(0, ZeroAddress);
      const balanceAfter = await ethers.provider.getBalance(alice.address);
      
      expect(balanceAfter - balanceBefore).to.equal(parseEther("5"));
    });

    it("should handle very small contributions", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      // 1 wei each
      await acp.connect(controller).contribute(0, alice.address, { value: 1n });
      await acp.connect(controller).contribute(0, bob.address, { value: 1n });
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      
      await acp.connect(controller).distribute(0, ZeroAddress);
      
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      
      expect(aliceAfter - aliceBefore).to.equal(1n);
      expect(bobAfter - bobBefore).to.equal(1n);
    });

    it("should handle uneven distribution (dust)", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      // 3 contributors, 10 wei total - can't divide evenly
      await acp.connect(controller).contribute(0, alice.address, { value: 3n });
      await acp.connect(controller).contribute(0, bob.address, { value: 3n });
      await acp.connect(controller).contribute(0, charlie.address, { value: 4n });
      
      // This should not revert - dust stays in contract
      await acp.connect(controller).distribute(0, ZeroAddress);
    });

    it("should revert on invalid pool ID", async function () {
      await expect(
        acp.connect(controller).contribute(999, alice.address, { value: parseEther("1") })
      ).to.be.reverted;
    });

    it("should handle zero balance distribution", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("1") });
      
      // Execute all funds out
      await acp.connect(controller).execute(0, controller.address, parseEther("1"), "0x");
      
      // Distribute with zero balance - should not revert, just send nothing
      await acp.connect(controller).distribute(0, ZeroAddress);
    });
  });

  describe("Access Control", function () {
    it("should prevent non-controller from all operations", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("1") });
      
      await expect(acp.connect(attacker).contribute(0, bob.address, { value: parseEther("1") }))
        .to.be.revertedWithCustomError(acp, "NotController");
      
      await expect(acp.connect(attacker).execute(0, bob.address, parseEther("0.5"), "0x"))
        .to.be.revertedWithCustomError(acp, "NotController");
      
      await expect(acp.connect(attacker).deposit(0, { value: parseEther("1") }))
        .to.be.revertedWithCustomError(acp, "NotController");
      
      await expect(acp.connect(attacker).distribute(0, ZeroAddress))
        .to.be.revertedWithCustomError(acp, "NotController");
    });

    it("should allow different controllers for different pools", async function () {
      await acp.connect(alice).createPool(ZeroAddress); // Pool 0, Alice controls
      await acp.connect(bob).createPool(ZeroAddress);   // Pool 1, Bob controls
      
      // Alice can operate on pool 0
      await acp.connect(alice).contribute(0, charlie.address, { value: parseEther("1") });
      
      // Bob can operate on pool 1
      await acp.connect(bob).contribute(1, charlie.address, { value: parseEther("1") });
      
      // Alice cannot operate on pool 1
      await expect(acp.connect(alice).contribute(1, charlie.address, { value: parseEther("1") }))
        .to.be.revertedWithCustomError(acp, "NotController");
      
      // Bob cannot operate on pool 0
      await expect(acp.connect(bob).distribute(0, ZeroAddress))
        .to.be.revertedWithCustomError(acp, "NotController");
    });
  });

  describe("Multiple Pools Isolation", function () {
    it("should keep pool balances separate", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).createPool(ZeroAddress);
      
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("10") });
      await acp.connect(controller).contribute(1, bob.address, { value: parseEther("5") });
      
      const [,,total0,] = await acp.getPoolInfo(0);
      const [,,total1,] = await acp.getPoolInfo(1);
      
      expect(total0).to.equal(parseEther("10"));
      expect(total1).to.equal(parseEther("5"));
    });

    it("should not allow cross-pool execution", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      await acp.connect(controller).createPool(ZeroAddress);
      
      await acp.connect(controller).contribute(0, alice.address, { value: parseEther("10") });
      
      // Try to execute more than pool 0 has (would need to steal from pool 1)
      await expect(
        acp.connect(controller).execute(0, bob.address, parseEther("15"), "0x")
      ).to.be.reverted;
    });
  });
});
