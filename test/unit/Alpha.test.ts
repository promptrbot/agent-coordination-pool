import { expect } from "chai";
import { ethers } from "hardhat";
import { ACP, MockERC20, MockWETH, MockAerodrome } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { parseEther, ZeroAddress } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// We need a modified Alpha that uses our mocks
describe("Alpha", function () {
  let acp: ACP;
  let weth: MockWETH;
  let targetToken: MockERC20;
  let router: MockAerodrome;
  let alpha: any; // AlphaTestable
  
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let charlie: SignerWithAddress;

  const ONE_HOUR = 3600;
  const ONE_DAY = 86400;

  beforeEach(async function () {
    [owner, alice, bob, charlie] = await ethers.getSigners();

    // Deploy mocks
    const WETHFactory = await ethers.getContractFactory("MockWETH");
    weth = await WETHFactory.deploy();

    const TokenFactory = await ethers.getContractFactory("MockERC20");
    targetToken = await TokenFactory.deploy("Target Token", "TGT", 18);

    const RouterFactory = await ethers.getContractFactory("MockAerodrome");
    router = await RouterFactory.deploy();

    // Deploy ACP
    const ACPFactory = await ethers.getContractFactory("ACP");
    acp = await ACPFactory.deploy();

    // Deploy testable Alpha with configurable addresses
    const AlphaFactory = await ethers.getContractFactory("AlphaTestable");
    alpha = await AlphaFactory.deploy(
      await acp.getAddress(),
      await router.getAddress(),
      await weth.getAddress()
    );

    // Fund router with tokens for swaps
    await targetToken.mint(await router.getAddress(), parseEther("1000000"));
    await weth.deposit({ value: parseEther("1000") });
    await weth.transfer(await router.getAddress(), parseEther("1000"));
    
    // Set exchange rate: 1 WETH = 1000 TGT tokens
    await router.setExchangeRate(await targetToken.getAddress(), 100000); // 10x
    await router.setExchangeRate(await weth.getAddress(), 1000); // 0.1x (reverse)
  });

  describe("Trade Creation", function () {
    it("should create a trade", async function () {
      const now = await time.latest();
      const buyTime = now + ONE_HOUR;
      const sellTime = now + ONE_DAY;
      const deadline = now + ONE_HOUR - 60;

      await alpha.create(
        await targetToken.getAddress(),
        parseEther("1"), // threshold
        buyTime,
        sellTime,
        deadline,
        200 // tickSpacing
      );

      const info = await alpha.getTradeInfo(0);
      expect(info.tokenOut).to.equal(await targetToken.getAddress());
      expect(info.threshold).to.equal(parseEther("1"));
      expect(info.status).to.equal(0); // Funding
    });

    it("should revert if deadline > buyTime", async function () {
      const now = await time.latest();
      
      await expect(alpha.create(
        await targetToken.getAddress(),
        parseEther("1"),
        now + ONE_HOUR,     // buyTime
        now + ONE_DAY,      // sellTime
        now + ONE_HOUR + 1, // deadline AFTER buyTime - invalid
        200
      )).to.be.revertedWith("deadline>buy");
    });

    it("should revert if sellTime <= buyTime", async function () {
      const now = await time.latest();
      
      await expect(alpha.create(
        await targetToken.getAddress(),
        parseEther("1"),
        now + ONE_HOUR,     // buyTime
        now + ONE_HOUR - 1, // sellTime BEFORE buyTime - invalid
        now + ONE_HOUR - 60,
        200
      )).to.be.revertedWith("sell<=buy");
    });
  });

  describe("Joining Trades", function () {
    let tradeId: number;
    let deadline: number;

    beforeEach(async function () {
      const now = await time.latest();
      deadline = now + ONE_HOUR - 60;
      
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        now + ONE_HOUR,
        now + ONE_DAY,
        deadline,
        200
      );
      tradeId = 0;
    });

    it("should allow joining with ETH", async function () {
      await alpha.connect(alice).join(tradeId, { value: parseEther("2") });
      
      expect(await alpha.getContribution(tradeId, alice.address)).to.equal(parseEther("2"));
    });

    it("should allow multiple contributors", async function () {
      await alpha.connect(alice).join(tradeId, { value: parseEther("2") });
      await alpha.connect(bob).join(tradeId, { value: parseEther("3") });
      
      const info = await alpha.getTradeInfo(tradeId);
      expect(info.totalContributed).to.equal(parseEther("5"));
      expect(info.contributorCount).to.equal(2);
    });

    it("should revert after deadline", async function () {
      await time.increaseTo(deadline + 1);
      
      await expect(
        alpha.connect(alice).join(tradeId, { value: parseEther("1") })
      ).to.be.revertedWith("closed");
    });

    it("should revert with zero value", async function () {
      await expect(
        alpha.connect(alice).join(tradeId, { value: 0 })
      ).to.be.revertedWith("no value");
    });
  });

  describe("Execute Buy", function () {
    let tradeId: number;
    let buyTime: number;

    beforeEach(async function () {
      const now = await time.latest();
      buyTime = now + ONE_HOUR;
      
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        buyTime,
        now + ONE_DAY,
        now + ONE_HOUR - 60,
        200
      );
      tradeId = 0;
      
      // Fund the trade
      await alpha.connect(alice).join(tradeId, { value: parseEther("2") });
      await alpha.connect(bob).join(tradeId, { value: parseEther("3") });
    });

    it("should execute buy when threshold met and time reached", async function () {
      await time.increaseTo(buyTime);
      
      await alpha.executeBuy(tradeId);
      
      const info = await alpha.getTradeInfo(tradeId);
      expect(info.status).to.equal(1); // Bought
    });

    it("should swap ETH for tokens via router", async function () {
      await time.increaseTo(buyTime);
      
      await alpha.executeBuy(tradeId);
      
      // Alpha should hold target tokens
      const alphaBalance = await targetToken.balanceOf(await alpha.getAddress());
      expect(alphaBalance).to.be.gt(0);
    });

    it("should revert if threshold not met", async function () {
      // Create new trade with higher threshold
      const now = await time.latest();
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("100"), // Very high threshold
        now + ONE_HOUR + 100,
        now + ONE_DAY + 100,
        now + ONE_HOUR + 50,
        200
      );
      
      await alpha.connect(alice).join(1, { value: parseEther("1") });
      await time.increaseTo(now + ONE_HOUR + 100);
      
      await expect(alpha.executeBuy(1)).to.be.revertedWith("threshold not met");
    });

    it("should revert if buyTime not reached", async function () {
      await expect(alpha.executeBuy(tradeId)).to.be.revertedWith("too early");
    });

    it("should revert if already bought", async function () {
      await time.increaseTo(buyTime);
      await alpha.executeBuy(tradeId);
      
      await expect(alpha.executeBuy(tradeId)).to.be.revertedWith("not funding");
    });
  });

  describe("Execute Sell", function () {
    let tradeId: number;
    let sellTime: number;

    beforeEach(async function () {
      const now = await time.latest();
      const buyTime = now + ONE_HOUR;
      sellTime = now + ONE_DAY;
      
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        buyTime,
        sellTime,
        now + ONE_HOUR - 60,
        200
      );
      tradeId = 0;
      
      // Fund and execute buy
      await alpha.connect(alice).join(tradeId, { value: parseEther("2") });
      await alpha.connect(bob).join(tradeId, { value: parseEther("3") });
      
      await time.increaseTo(buyTime);
      await alpha.executeBuy(tradeId);
    });

    it("should execute sell when time reached", async function () {
      await time.increaseTo(sellTime);
      
      await alpha.executeSell(tradeId);
      
      const info = await alpha.getTradeInfo(tradeId);
      expect(info.status).to.equal(2); // Sold
    });

    it("should swap tokens back to ETH", async function () {
      await time.increaseTo(sellTime);
      
      const acpBalanceBefore = await ethers.provider.getBalance(await acp.getAddress());
      await alpha.executeSell(tradeId);
      const acpBalanceAfter = await ethers.provider.getBalance(await acp.getAddress());
      
      // ACP should have received ETH back
      expect(acpBalanceAfter).to.be.gt(acpBalanceBefore);
    });

    it("should revert if sellTime not reached", async function () {
      await expect(alpha.executeSell(tradeId)).to.be.revertedWith("too early");
    });

    it("should revert if not in Bought status", async function () {
      // Create new trade, don't buy
      const now = await time.latest();
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("1"),
        now + 100,
        now + 200,
        now + 50,
        200
      );
      await alpha.connect(alice).join(1, { value: parseEther("1") });
      
      await time.increaseTo(now + 200);
      
      await expect(alpha.executeSell(1)).to.be.revertedWith("not bought");
    });
  });

  describe("Claim", function () {
    let tradeId: number;

    beforeEach(async function () {
      const now = await time.latest();
      const buyTime = now + ONE_HOUR;
      const sellTime = now + ONE_DAY;
      
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        buyTime,
        sellTime,
        now + ONE_HOUR - 60,
        200
      );
      tradeId = 0;
      
      // Alice: 2 ETH (40%), Bob: 3 ETH (60%)
      await alpha.connect(alice).join(tradeId, { value: parseEther("2") });
      await alpha.connect(bob).join(tradeId, { value: parseEther("3") });
      
      await time.increaseTo(buyTime);
      await alpha.executeBuy(tradeId);
      
      await time.increaseTo(sellTime);
      await alpha.executeSell(tradeId);
    });

    it("should distribute ETH pro-rata", async function () {
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      
      await alpha.claim(tradeId);
      
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      
      // Both should receive something
      expect(aliceAfter).to.be.gt(aliceBefore);
      expect(bobAfter).to.be.gt(bobBefore);
    });

    it("should revert if not sold", async function () {
      // Create new trade, only buy
      const now = await time.latest();
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("1"),
        now + 100,
        now + 200,
        now + 50,
        200
      );
      await alpha.connect(alice).join(1, { value: parseEther("1") });
      await time.increaseTo(now + 100);
      await alpha.executeBuy(1);
      
      await expect(alpha.claim(1)).to.be.revertedWith("not sold");
    });
  });

  describe("Withdraw (Expired)", function () {
    let tradeId: number;
    let deadline: number;

    beforeEach(async function () {
      const now = await time.latest();
      deadline = now + ONE_HOUR - 60;
      
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("100"), // High threshold - won't be met
        now + ONE_HOUR,
        now + ONE_DAY,
        deadline,
        200
      );
      tradeId = 0;
      
      await alpha.connect(alice).join(tradeId, { value: parseEther("2") });
      await alpha.connect(bob).join(tradeId, { value: parseEther("3") });
    });

    it("should refund contributors when expired", async function () {
      await time.increaseTo(deadline + 1);
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      
      await alpha.withdraw(tradeId);
      
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      
      expect(aliceAfter - aliceBefore).to.equal(parseEther("2"));
      expect(bobAfter - bobBefore).to.equal(parseEther("3"));
    });

    it("should revert if deadline not passed", async function () {
      await expect(alpha.withdraw(tradeId)).to.be.revertedWith("cannot");
    });

    it("should revert if already bought", async function () {
      // Create trade that will meet threshold
      const now = await time.latest();
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("1"),
        now + 1000,
        now + 2000,
        now + 900,
        200
      );
      await alpha.connect(alice).join(1, { value: parseEther("1") });
      await time.increaseTo(now + 1000);
      await alpha.executeBuy(1);
      
      await time.increaseTo(now + 1000);
      
      await expect(alpha.withdraw(1)).to.be.revertedWith("cannot");
    });
  });

  describe("Profit/Loss Scenarios", function () {
    it("should distribute profits when price goes up", async function () {
      // Set favorable exchange rate: sell gets more ETH back
      await router.setExchangeRate(await targetToken.getAddress(), 100000); // 10x on buy
      await router.setExchangeRate(await weth.getAddress(), 2000); // 0.2x on sell (profit)
      
      const now = await time.latest();
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        now + 100,
        now + 200,
        now + 50,
        200
      );
      
      await alpha.connect(alice).join(0, { value: parseEther("5") });
      
      await time.increaseTo(now + 100);
      await alpha.executeBuy(0);
      
      await time.increaseTo(now + 200);
      await alpha.executeSell(0);
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      await alpha.claim(0);
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      
      // Should have profit
      expect(aliceAfter - aliceBefore).to.be.gt(parseEther("5"));
    });

    it("should distribute losses when price goes down", async function () {
      // Set unfavorable exchange rate
      await router.setExchangeRate(await targetToken.getAddress(), 100000); // 10x on buy
      await router.setExchangeRate(await weth.getAddress(), 500); // 0.05x on sell (loss)
      
      const now = await time.latest();
      await alpha.create(
        await targetToken.getAddress(),
        parseEther("5"),
        now + 100,
        now + 200,
        now + 50,
        200
      );
      
      await alpha.connect(alice).join(0, { value: parseEther("5") });
      
      await time.increaseTo(now + 100);
      await alpha.executeBuy(0);
      
      await time.increaseTo(now + 200);
      await alpha.executeSell(0);
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      await alpha.claim(0);
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      
      // Should have loss
      expect(aliceAfter - aliceBefore).to.be.lt(parseEther("5"));
    });
  });
});
