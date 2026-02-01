import { expect } from "chai";
import { ethers } from "hardhat";
import { ACP, MockERC20 } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { ZeroAddress } from "ethers";

describe("ACP Fuzz Tests", function () {
  let acp: ACP;
  let token: MockERC20;
  let controller: SignerWithAddress;
  let signers: SignerWithAddress[];

  beforeEach(async function () {
    signers = await ethers.getSigners();
    controller = signers[0];

    const ACPFactory = await ethers.getContractFactory("ACP");
    acp = await ACPFactory.deploy();

    const TokenFactory = await ethers.getContractFactory("MockERC20");
    token = await TokenFactory.deploy("Test", "TEST", 18);
  });

  // Helper: generate random BigInt in range
  function randomBigInt(min: bigint, max: bigint): bigint {
    const range = max - min;
    const random = BigInt(Math.floor(Math.random() * Number(range)));
    return min + random;
  }

  // Helper: generate random contributions
  function generateContributions(numContributors: number, minAmount: bigint, maxAmount: bigint): bigint[] {
    const contributions: bigint[] = [];
    for (let i = 0; i < numContributors; i++) {
      contributions.push(randomBigInt(minAmount, maxAmount));
    }
    return contributions;
  }

  describe("Random Contribution Amounts", function () {
    it("should handle random contribution amounts correctly", async function () {
      this.timeout(60000);
      
      const iterations = 20;
      
      for (let i = 0; i < iterations; i++) {
        // Create pool
        await acp.connect(controller).createPool(ZeroAddress);
        const poolId = i;
        
        // Random number of contributors (1-10)
        const numContributors = Math.floor(Math.random() * 10) + 1;
        const contributions = generateContributions(
          numContributors,
          1n, // min 1 wei
          10n ** 18n // max 1 ETH
        );
        
        let totalExpected = 0n;
        
        // Contribute
        for (let j = 0; j < numContributors; j++) {
          const contributor = signers[j + 1]; // Skip controller
          await acp.connect(controller).contribute(poolId, contributor.address, { value: contributions[j] });
          totalExpected += contributions[j];
        }
        
        // Verify total
        const [,,totalContributed, contributorCount] = await acp.getPoolInfo(poolId);
        expect(totalContributed).to.equal(totalExpected);
        expect(contributorCount).to.equal(numContributors);
        
        // Verify individual contributions
        for (let j = 0; j < numContributors; j++) {
          const contributor = signers[j + 1];
          expect(await acp.getContribution(poolId, contributor.address)).to.equal(contributions[j]);
        }
      }
    });
  });

  describe("Distribution Invariants", function () {
    it("should maintain conservation of value after distribution", async function () {
      this.timeout(60000);
      
      const iterations = 10;
      
      for (let i = 0; i < iterations; i++) {
        await acp.connect(controller).createPool(ZeroAddress);
        const poolId = i;
        
        const numContributors = Math.floor(Math.random() * 5) + 2; // 2-6 contributors
        const contributions = generateContributions(
          numContributors,
          10n ** 15n, // min 0.001 ETH
          10n ** 18n  // max 1 ETH
        );
        
        let totalContributed = 0n;
        const contributorAddresses: string[] = [];
        
        for (let j = 0; j < numContributors; j++) {
          const contributor = signers[j + 1];
          contributorAddresses.push(contributor.address);
          await acp.connect(controller).contribute(poolId, contributor.address, { value: contributions[j] });
          totalContributed += contributions[j];
        }
        
        // Get balances before distribution
        const balancesBefore = await Promise.all(
          contributorAddresses.map(addr => ethers.provider.getBalance(addr))
        );
        
        // Distribute
        await acp.connect(controller).distribute(poolId, ZeroAddress);
        
        // Get balances after
        const balancesAfter = await Promise.all(
          contributorAddresses.map(addr => ethers.provider.getBalance(addr))
        );
        
        // Calculate total received
        let totalReceived = 0n;
        for (let j = 0; j < numContributors; j++) {
          totalReceived += balancesAfter[j] - balancesBefore[j];
        }
        
        // Total received should equal total contributed (minus dust)
        // Allow for small rounding errors (up to numContributors wei)
        const dust = totalContributed - totalReceived;
        expect(dust).to.be.lte(BigInt(numContributors));
        expect(dust).to.be.gte(0n);
      }
    });

    it("should maintain proportionality in distribution", async function () {
      this.timeout(60000);
      
      const iterations = 10;
      
      for (let i = 0; i < iterations; i++) {
        await acp.connect(controller).createPool(ZeroAddress);
        const poolId = i;
        
        // Use exactly 2 contributors for easy ratio checking
        const alice = signers[1];
        const bob = signers[2];
        
        // Random contributions
        const aliceContribution = randomBigInt(10n ** 17n, 10n ** 19n);
        const bobContribution = randomBigInt(10n ** 17n, 10n ** 19n);
        
        await acp.connect(controller).contribute(poolId, alice.address, { value: aliceContribution });
        await acp.connect(controller).contribute(poolId, bob.address, { value: bobContribution });
        
        const total = aliceContribution + bobContribution;
        
        const aliceBefore = await ethers.provider.getBalance(alice.address);
        const bobBefore = await ethers.provider.getBalance(bob.address);
        
        await acp.connect(controller).distribute(poolId, ZeroAddress);
        
        const aliceAfter = await ethers.provider.getBalance(alice.address);
        const bobAfter = await ethers.provider.getBalance(bob.address);
        
        const aliceReceived = aliceAfter - aliceBefore;
        const bobReceived = bobAfter - bobBefore;
        
        // Check proportionality: alice/bob ≈ aliceContribution/bobContribution
        // Use cross multiplication to avoid division: alice * bobContrib ≈ bob * aliceContrib
        const cross1 = aliceReceived * bobContribution;
        const cross2 = bobReceived * aliceContribution;
        
        // Allow 0.01% tolerance for rounding
        const tolerance = (cross1 > cross2 ? cross1 : cross2) / 10000n;
        const diff = cross1 > cross2 ? cross1 - cross2 : cross2 - cross1;
        
        expect(diff).to.be.lte(tolerance);
      }
    });
  });

  describe("Extreme Values", function () {
    it("should handle minimum value (1 wei)", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      await acp.connect(controller).contribute(0, signers[1].address, { value: 1n });
      
      expect(await acp.getContribution(0, signers[1].address)).to.equal(1n);
    });

    it("should handle large value (1000 ETH)", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      const largeAmount = 10n ** 21n; // 1000 ETH
      await acp.connect(controller).contribute(0, signers[1].address, { value: largeAmount });
      
      expect(await acp.getContribution(0, signers[1].address)).to.equal(largeAmount);
    });

    it("should handle many small contributors", async function () {
      this.timeout(120000);
      
      await acp.connect(controller).createPool(ZeroAddress);
      
      // 50 contributors with 0.01 ETH each
      const numContributors = 50;
      const amount = 10n ** 16n;
      
      for (let i = 1; i <= numContributors; i++) {
        await acp.connect(controller).contribute(0, signers[i % 20].address, { value: amount });
      }
      
      const [,,total,] = await acp.getPoolInfo(0);
      expect(total).to.equal(amount * BigInt(numContributors));
    });

    it("should handle whale + many small contributors", async function () {
      this.timeout(60000);
      
      await acp.connect(controller).createPool(ZeroAddress);
      
      // Whale: 100 ETH
      const whale = signers[1];
      await acp.connect(controller).contribute(0, whale.address, { value: 10n ** 20n });
      
      // 10 small: 0.01 ETH each
      for (let i = 2; i <= 11; i++) {
        await acp.connect(controller).contribute(0, signers[i].address, { value: 10n ** 16n });
      }
      
      const whaleBefore = await ethers.provider.getBalance(whale.address);
      
      await acp.connect(controller).distribute(0, ZeroAddress);
      
      const whaleAfter = await ethers.provider.getBalance(whale.address);
      
      // Whale should get ~99% of funds
      const total = 10n ** 20n + 10n ** 17n; // 100.1 ETH
      const whaleShare = whaleAfter - whaleBefore;
      
      // Whale contributed 100/100.1 ≈ 99.9%
      expect(whaleShare).to.be.gt(total * 99n / 100n);
    });
  });

  describe("Token Distribution Fuzz", function () {
    it("should distribute ERC20 tokens correctly with random amounts", async function () {
      this.timeout(60000);
      
      await acp.connect(controller).createPool(ZeroAddress);
      
      const numContributors = 5;
      const contributions = generateContributions(
        numContributors,
        10n ** 17n,
        10n ** 18n
      );
      
      let total = 0n;
      for (let i = 0; i < numContributors; i++) {
        await acp.connect(controller).contribute(0, signers[i + 1].address, { value: contributions[i] });
        total += contributions[i];
      }
      
      // Mint random amount of tokens to ACP
      const tokenAmount = randomBigInt(10n ** 20n, 10n ** 24n);
      await token.mint(await acp.getAddress(), tokenAmount);
      
      // Get balances before
      const balancesBefore = await Promise.all(
        Array.from({ length: numContributors }, (_, i) => token.balanceOf(signers[i + 1].address))
      );
      
      await acp.connect(controller).distribute(0, await token.getAddress());
      
      // Get balances after
      const balancesAfter = await Promise.all(
        Array.from({ length: numContributors }, (_, i) => token.balanceOf(signers[i + 1].address))
      );
      
      // Verify proportionality
      let totalReceived = 0n;
      for (let i = 0; i < numContributors; i++) {
        const received = balancesAfter[i] - balancesBefore[i];
        totalReceived += received;
        
        // Expected share: (contribution / total) * tokenAmount
        const expectedShare = (contributions[i] * tokenAmount) / total;
        
        // Allow 1 wei tolerance per token transferred
        expect(received).to.be.closeTo(expectedShare, 1);
      }
      
      // Total received should be close to tokenAmount
      expect(totalReceived).to.be.closeTo(tokenAmount, BigInt(numContributors));
    });
  });

  describe("Repeated Operations", function () {
    it("should handle repeated contributions from same address", async function () {
      await acp.connect(controller).createPool(ZeroAddress);
      
      const contributor = signers[1];
      const iterations = 20;
      let total = 0n;
      
      for (let i = 0; i < iterations; i++) {
        const amount = randomBigInt(10n ** 15n, 10n ** 17n);
        await acp.connect(controller).contribute(0, contributor.address, { value: amount });
        total += amount;
      }
      
      expect(await acp.getContribution(0, contributor.address)).to.equal(total);
      
      const [,,,count] = await acp.getPoolInfo(0);
      expect(count).to.equal(1); // Still just one contributor
    });
  });
});
