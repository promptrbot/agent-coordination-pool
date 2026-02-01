import { expect } from "chai";
import { ethers } from "hardhat";
import { ACP, MockERC20, MockWETH, MockAerodrome, MockClanker, MockClankerFeeLocker } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { parseEther, ZeroAddress } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("E2E Integration Tests", function () {
  let acp: ACP;
  let weth: MockWETH;
  let targetToken: MockERC20;
  let router: MockAerodrome;
  let clanker: MockClanker;
  let feeLocker: MockClankerFeeLocker;
  let alpha: any;
  let launchpad: any;
  
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let charlie: SignerWithAddress;
  let dave: SignerWithAddress;

  const ONE_HOUR = 3600;
  const ONE_DAY = 86400;

  beforeEach(async function () {
    [owner, alice, bob, charlie, dave] = await ethers.getSigners();

    // Deploy all mocks
    const WETHFactory = await ethers.getContractFactory("MockWETH");
    weth = await WETHFactory.deploy();

    const TokenFactory = await ethers.getContractFactory("MockERC20");
    targetToken = await TokenFactory.deploy("Target Token", "TGT", 18);

    const RouterFactory = await ethers.getContractFactory("MockAerodrome");
    router = await RouterFactory.deploy();

    const ClankerFactory = await ethers.getContractFactory("MockClanker");
    clanker = await ClankerFactory.deploy();

    const FeeLockerFactory = await ethers.getContractFactory("MockClankerFeeLocker");
    feeLocker = await FeeLockerFactory.deploy(await weth.getAddress());

    // Deploy ACP
    const ACPFactory = await ethers.getContractFactory("ACP");
    acp = await ACPFactory.deploy();

    // Deploy Alpha
    const AlphaFactory = await ethers.getContractFactory("AlphaTestable");
    alpha = await AlphaFactory.deploy(
      await acp.getAddress(),
      await router.getAddress(),
      await weth.getAddress()
    );

    // Deploy Launchpad
    const LaunchpadFactory = await ethers.getContractFactory("LaunchpadTestable");
    launchpad = await LaunchpadFactory.deploy(
      await acp.getAddress(),
      await clanker.getAddress(),
      await weth.getAddress(),
      await feeLocker.getAddress()
    );

    // Fund router for swaps
    await targetToken.mint(await router.getAddress(), parseEther("10000000"));
    await weth.deposit({ value: parseEther("10000") });
    await weth.transfer(await router.getAddress(), parseEther("10000"));
    
    // 1 WETH = 1000 TGT, 1000 TGT = 1.2 WETH (20% profit)
    await router.setExchangeRate(await targetToken.getAddress(), 100000); // 10x
    await router.setExchangeRate(await weth.getAddress(), 1200); // 0.12x
  });

  describe("Alpha Full Flow", function () {
    it("should complete profitable trade with multiple contributors", async function () {
      const now = await time.latest();
      const buyTime = now + ONE_HOUR;
      const sellTime = now + ONE_DAY;
      const deadline = now + ONE_HOUR - 60;

      // Create trade
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        buyTime,
        sellTime,
        deadline,
        200
      );

      // Multiple contributors join
      // Alice: 2 ETH (40%), Bob: 2 ETH (40%), Charlie: 1 ETH (20%)
      await alpha.connect(alice).join(0, { value: parseEther("2") });
      await alpha.connect(bob).join(0, { value: parseEther("2") });
      await alpha.connect(charlie).join(0, { value: parseEther("1") });

      // Record balances before
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      const charlieBefore = await ethers.provider.getBalance(charlie.address);

      // Execute buy
      await time.increaseTo(buyTime);
      await alpha.executeBuy(0);

      // Verify tokens held
      const info = await alpha.getTradeInfo(0);
      expect(info.tokensHeld).to.be.gt(0);
      expect(info.status).to.equal(1); // Bought

      // Execute sell
      await time.increaseTo(sellTime);
      await alpha.executeSell(0);

      expect((await alpha.getTradeInfo(0)).status).to.equal(2); // Sold

      // Claim
      await alpha.claim(0);

      // Check profits
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      const charlieAfter = await ethers.provider.getBalance(charlie.address);

      // All should have profit (20% based on mock exchange rate)
      expect(aliceAfter).to.be.gt(aliceBefore);
      expect(bobAfter).to.be.gt(bobBefore);
      expect(charlieAfter).to.be.gt(charlieBefore);

      // Check proportionality: Alice and Bob should get same, Charlie half
      const aliceProfit = aliceAfter - aliceBefore;
      const bobProfit = bobAfter - bobBefore;
      const charlieProfit = charlieAfter - charlieBefore;

      expect(aliceProfit).to.be.closeTo(bobProfit, parseEther("0.001"));
      expect(charlieProfit).to.be.closeTo(aliceProfit / 2n, parseEther("0.001"));
    });

    it("should refund on expired trade", async function () {
      const now = await time.latest();
      
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("100"), // High threshold - won't be met
        now + ONE_HOUR,
        now + ONE_DAY,
        now + ONE_HOUR - 60,
        200
      );

      await alpha.connect(alice).join(0, { value: parseEther("5") });
      await alpha.connect(bob).join(0, { value: parseEther("3") });

      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);

      // Wait for deadline to pass
      await time.increaseTo(now + ONE_HOUR);

      // Withdraw
      await alpha.withdraw(0);

      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);

      // Full refund
      expect(aliceAfter - aliceBefore).to.equal(parseEther("5"));
      expect(bobAfter - bobBefore).to.equal(parseEther("3"));
    });
  });

  describe("Launchpad Full Flow", function () {
    it("should complete launch and distribute tokens", async function () {
      const now = await time.latest();
      const deadline = now + ONE_DAY;

      // Create launch
      await launchpad.create(
        "Community Token",
        "COMM",
        "https://example.com/logo.png",
        parseEther("5"),
        deadline
      );

      // Contributors join
      // Alice: 2 ETH (40%), Bob: 3 ETH (60%)
      await launchpad.connect(alice).join(0, { value: parseEther("2") });
      await launchpad.connect(bob).join(0, { value: parseEther("3") });

      // Launch
      await launchpad.launch(0);

      // Get token address
      const info = await launchpad.getLaunchInfo(0);
      expect(info.status).to.equal(1); // Launched
      expect(info.token).to.not.equal(ZeroAddress);

      const token = await ethers.getContractAt("MockClankerToken", info.token);

      // Claim tokens
      await launchpad.claim(0);

      // Check token distribution
      const aliceTokens = await token.balanceOf(alice.address);
      const bobTokens = await token.balanceOf(bob.address);

      expect(aliceTokens).to.be.gt(0);
      expect(bobTokens).to.be.gt(0);

      // Bob should have 1.5x more (60/40)
      const ratio = bobTokens * 10000n / aliceTokens;
      expect(ratio).to.be.closeTo(15000n, 100n);
    });

    it("should distribute LP fees to contributors", async function () {
      const now = await time.latest();

      await launchpad.create("Fee Token", "FEE", "", parseEther("5"), now + ONE_DAY);
      
      await launchpad.connect(alice).join(0, { value: parseEther("2") });
      await launchpad.connect(bob).join(0, { value: parseEther("3") });

      await launchpad.launch(0);

      // Claim initial tokens
      await launchpad.claim(0);

      const info = await launchpad.getLaunchInfo(0);

      // Simulate fee accumulation
      await weth.deposit({ value: parseEther("10") });
      await weth.transfer(await feeLocker.getAddress(), parseEther("10"));
      await feeLocker.addFees(await launchpad.getAddress(), info.token, parseEther("10"), 0);

      // Check available fees
      const [wethFees,] = await launchpad.availableFees(0);
      expect(wethFees).to.equal(parseEther("10"));

      // Record WETH balances
      const aliceWethBefore = await weth.balanceOf(alice.address);
      const bobWethBefore = await weth.balanceOf(bob.address);

      // Claim fees
      await launchpad.claimFees(0);

      // Check distribution
      const aliceWethAfter = await weth.balanceOf(alice.address);
      const bobWethAfter = await weth.balanceOf(bob.address);

      // Alice: 40% = 4 WETH, Bob: 60% = 6 WETH
      expect(aliceWethAfter - aliceWethBefore).to.equal(parseEther("4"));
      expect(bobWethAfter - bobWethBefore).to.equal(parseEther("6"));
    });
  });

  describe("Multiple Concurrent Operations", function () {
    it("should handle multiple Alpha trades simultaneously", async function () {
      const now = await time.latest();

      // Create 3 trades
      for (let i = 0; i < 3; i++) {
        await alpha.create(
          await targetToken.getAddress(),
          parseEther("1"),
          now + ONE_HOUR * (i + 1),
          now + ONE_DAY + ONE_HOUR * (i + 1),
          now + ONE_HOUR * (i + 1) - 60,
          200
        );

        await alpha.connect(alice).join(i, { value: parseEther("1") });
      }

      // Execute first trade
      await time.increaseTo(now + ONE_HOUR);
      await alpha.executeBuy(0);

      // Second and third still funding
      expect((await alpha.getTradeInfo(0)).status).to.equal(1);
      expect((await alpha.getTradeInfo(1)).status).to.equal(0);
      expect((await alpha.getTradeInfo(2)).status).to.equal(0);

      // Execute second trade
      await time.increaseTo(now + ONE_HOUR * 2);
      await alpha.executeBuy(1);

      // First can now sell
      await time.increaseTo(now + ONE_DAY + ONE_HOUR);
      await alpha.executeSell(0);
      await alpha.claim(0);

      expect((await alpha.getTradeInfo(0)).status).to.equal(2);
    });

    it("should handle Alpha and Launchpad using same ACP", async function () {
      const now = await time.latest();

      // Create Alpha trade
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("2"),
        now + ONE_HOUR,
        now + ONE_DAY,
        now + ONE_HOUR - 60,
        200
      );

      // Create Launchpad
      await launchpad.create("Mixed", "MIX", "", parseEther("2"), now + ONE_DAY);

      // Alice joins both
      await alpha.connect(alice).join(0, { value: parseEther("1") });
      await launchpad.connect(alice).join(0, { value: parseEther("1") });

      // Bob joins both
      await alpha.connect(bob).join(0, { value: parseEther("1") });
      await launchpad.connect(bob).join(0, { value: parseEther("1") });

      // ACP should have 2 pools (one per use case)
      expect(await acp.poolCount()).to.equal(2);

      // Execute Alpha trade
      await time.increaseTo(now + ONE_HOUR);
      await alpha.executeBuy(0);
      await time.increaseTo(now + ONE_DAY);
      await alpha.executeSell(0);

      // Launch token
      await launchpad.launch(0);

      // Both should work independently
      await alpha.claim(0);
      await launchpad.claim(0);
    });
  });

  describe("Edge Case Flows", function () {
    it("should handle single contributor getting everything", async function () {
      const now = await time.latest();

      await launchpad.create("Solo", "SOLO", "", parseEther("1"), now + ONE_DAY);
      await launchpad.connect(alice).join(0, { value: parseEther("1") });
      await launchpad.launch(0);

      const info = await launchpad.getLaunchInfo(0);
      const token = await ethers.getContractAt("MockClankerToken", info.token);

      const acpBalance = await token.balanceOf(await acp.getAddress());

      await launchpad.claim(0);

      // Alice should get all tokens
      const aliceBalance = await token.balanceOf(alice.address);
      expect(aliceBalance).to.equal(acpBalance);
    });

    it("should handle very unequal contributions", async function () {
      const now = await time.latest();

      await alpha.create(
        await targetToken.getAddress(),
        parseEther("100"),
        now + ONE_HOUR,
        now + ONE_DAY,
        now + ONE_HOUR - 60,
        200
      );

      // Whale: 99 ETH, Small: 1 ETH
      await alpha.connect(alice).join(0, { value: parseEther("99") });
      await alpha.connect(bob).join(0, { value: parseEther("1") });

      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);

      await time.increaseTo(now + ONE_HOUR);
      await alpha.executeBuy(0);
      await time.increaseTo(now + ONE_DAY);
      await alpha.executeSell(0);
      await alpha.claim(0);

      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);

      // Alice should get ~99%, Bob ~1%
      const totalReceived = (aliceAfter - aliceBefore) + (bobAfter - bobBefore);
      const aliceShare = (aliceAfter - aliceBefore) * 10000n / totalReceived;

      expect(aliceShare).to.be.closeTo(9900n, 50n); // ~99%
    });

    it("should handle rapid successive operations", async function () {
      const now = await time.latest();

      // Create many launches quickly
      for (let i = 0; i < 10; i++) {
        await launchpad.create(`Token${i}`, `TKN${i}`, "", parseEther("0.1"), now + ONE_DAY);
        await launchpad.connect(alice).join(i, { value: parseEther("0.1") });
        await launchpad.launch(i);
        await launchpad.claim(i);
      }

      expect(await launchpad.count()).to.equal(10);
      expect(await clanker.deploymentCount()).to.equal(10);
    });
  });

  describe("Security Scenarios", function () {
    it("should prevent double claiming", async function () {
      const now = await time.latest();

      await launchpad.create("Double", "DBL", "", parseEther("1"), now + ONE_DAY);
      await launchpad.connect(alice).join(0, { value: parseEther("1") });
      await launchpad.launch(0);

      await launchpad.claim(0);

      // Second claim should fail or do nothing (depends on ACP impl)
      // The distribute function in ACP will have 0 balance second time
      await launchpad.claim(0); // Should not revert, but also not send anything

      const info = await launchpad.getLaunchInfo(0);
      const token = await ethers.getContractAt("MockClankerToken", info.token);
      
      // ACP should have 0 tokens left
      expect(await token.balanceOf(await acp.getAddress())).to.equal(0);
    });

    it("should isolate pools from each other", async function () {
      const now = await time.latest();

      // Create two launches
      await launchpad.create("Pool1", "P1", "", parseEther("10"), now + ONE_DAY);
      await launchpad.create("Pool2", "P2", "", parseEther("1"), now + ONE_DAY);

      // Fund pool 1 heavily
      await launchpad.connect(alice).join(0, { value: parseEther("10") });
      
      // Fund pool 2 minimally
      await launchpad.connect(bob).join(1, { value: parseEther("1") });

      // Launch pool 2 only
      await launchpad.launch(1);

      // Pool 1 should still be funding
      const info0 = await launchpad.getLaunchInfo(0);
      const info1 = await launchpad.getLaunchInfo(1);

      expect(info0.status).to.equal(0); // Still funding
      expect(info1.status).to.equal(1); // Launched

      // Alice's contribution to pool 1 should be intact
      expect(await launchpad.getContribution(0, alice.address)).to.equal(parseEther("10"));
    });
  });
});
