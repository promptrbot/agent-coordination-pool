import { expect } from "chai";
import { ethers } from "hardhat";
import { ACP, MockWETH, MockClanker, MockClankerFeeLocker } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { parseEther, ZeroAddress } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("Launchpad", function () {
  let acp: ACP;
  let weth: MockWETH;
  let clanker: MockClanker;
  let feeLocker: MockClankerFeeLocker;
  let launchpad: any; // LaunchpadTestable
  
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let charlie: SignerWithAddress;

  const ONE_DAY = 86400;

  beforeEach(async function () {
    [owner, alice, bob, charlie] = await ethers.getSigners();

    // Deploy mocks
    const WETHFactory = await ethers.getContractFactory("MockWETH");
    weth = await WETHFactory.deploy();

    const ClankerFactory = await ethers.getContractFactory("MockClanker");
    clanker = await ClankerFactory.deploy();

    const FeeLockerFactory = await ethers.getContractFactory("MockClankerFeeLocker");
    feeLocker = await FeeLockerFactory.deploy(await weth.getAddress());

    // Deploy ACP
    const ACPFactory = await ethers.getContractFactory("ACP");
    acp = await ACPFactory.deploy();

    // Deploy testable Launchpad
    const LaunchpadFactory = await ethers.getContractFactory("LaunchpadTestable");
    launchpad = await LaunchpadFactory.deploy(
      await acp.getAddress(),
      await clanker.getAddress(),
      await weth.getAddress(),
      await feeLocker.getAddress()
    );
  });

  describe("Launch Creation", function () {
    it("should create a launch", async function () {
      const now = await time.latest();
      const deadline = now + ONE_DAY;

      await launchpad.create(
        "Test Token",
        "TEST",
        "https://example.com/image.png",
        parseEther("5"),
        deadline
      );

      const info = await launchpad.getLaunchInfo(0);
      expect(info.name).to.equal("Test Token");
      expect(info.symbol).to.equal("TEST");
      expect(info.threshold).to.equal(parseEther("5"));
      expect(info.status).to.equal(0); // Funding
    });

    it("should revert with empty name", async function () {
      const now = await time.latest();
      
      await expect(launchpad.create(
        "",
        "TEST",
        "",
        parseEther("5"),
        now + ONE_DAY
      )).to.be.revertedWith("empty");
    });

    it("should revert with empty symbol", async function () {
      const now = await time.latest();
      
      await expect(launchpad.create(
        "Test",
        "",
        "",
        parseEther("5"),
        now + ONE_DAY
      )).to.be.revertedWith("empty");
    });

    it("should revert with zero threshold", async function () {
      const now = await time.latest();
      
      await expect(launchpad.create(
        "Test",
        "TEST",
        "",
        0,
        now + ONE_DAY
      )).to.be.revertedWith("invalid");
    });

    it("should revert with past deadline", async function () {
      const now = await time.latest();
      
      await expect(launchpad.create(
        "Test",
        "TEST",
        "",
        parseEther("5"),
        now - 1
      )).to.be.revertedWith("invalid");
    });

    it("should emit LaunchCreated event", async function () {
      const now = await time.latest();
      
      await expect(launchpad.create("Test", "TEST", "", parseEther("5"), now + ONE_DAY))
        .to.emit(launchpad, "LaunchCreated")
        .withArgs(0, "Test", "TEST", parseEther("5"));
    });
  });

  describe("Joining Launches", function () {
    let launchId: number;
    let deadline: number;

    beforeEach(async function () {
      const now = await time.latest();
      deadline = now + ONE_DAY;
      
      await launchpad.create("Test", "TEST", "", parseEther("5"), deadline);
      launchId = 0;
    });

    it("should allow joining with ETH", async function () {
      await launchpad.connect(alice).join(launchId, { value: parseEther("2") });
      
      expect(await launchpad.getContribution(launchId, alice.address)).to.equal(parseEther("2"));
    });

    it("should allow multiple contributors", async function () {
      await launchpad.connect(alice).join(launchId, { value: parseEther("2") });
      await launchpad.connect(bob).join(launchId, { value: parseEther("3") });
      
      const info = await launchpad.getLaunchInfo(launchId);
      expect(info.totalContributed).to.equal(parseEther("5"));
      expect(info.contributorCount).to.equal(2);
    });

    it("should revert after deadline", async function () {
      await time.increaseTo(deadline + 1);
      
      await expect(
        launchpad.connect(alice).join(launchId, { value: parseEther("1") })
      ).to.be.revertedWith("closed");
    });

    it("should revert with zero value", async function () {
      await expect(
        launchpad.connect(alice).join(launchId, { value: 0 })
      ).to.be.revertedWith("no value");
    });
  });

  describe("Launch Execution", function () {
    let launchId: number;

    beforeEach(async function () {
      const now = await time.latest();
      
      await launchpad.create("Test", "TEST", "", parseEther("5"), now + ONE_DAY);
      launchId = 0;
      
      // Fund the launch
      await launchpad.connect(alice).join(launchId, { value: parseEther("2") });
      await launchpad.connect(bob).join(launchId, { value: parseEther("3") });
    });

    it("should deploy token via Clanker", async function () {
      await launchpad.launch(launchId);
      
      const info = await launchpad.getLaunchInfo(launchId);
      expect(info.status).to.equal(1); // Launched
      expect(info.token).to.not.equal(ZeroAddress);
    });

    it("should emit Launched event", async function () {
      const tx = await launchpad.launch(launchId);
      
      await expect(tx).to.emit(launchpad, "Launched");
    });

    it("should revert if threshold not met", async function () {
      // Create new launch with higher threshold
      const now = await time.latest();
      await launchpad.create("High", "HIGH", "", parseEther("100"), now + ONE_DAY);
      await launchpad.connect(alice).join(1, { value: parseEther("1") });
      
      await expect(launchpad.launch(1)).to.be.revertedWith("threshold not met");
    });

    it("should revert if already launched", async function () {
      await launchpad.launch(launchId);
      
      await expect(launchpad.launch(launchId)).to.be.revertedWith("not funding");
    });
  });

  describe("Token Claiming", function () {
    let launchId: number;

    beforeEach(async function () {
      const now = await time.latest();
      
      await launchpad.create("Test", "TEST", "", parseEther("5"), now + ONE_DAY);
      launchId = 0;
      
      // Alice: 2 ETH (40%), Bob: 3 ETH (60%)
      await launchpad.connect(alice).join(launchId, { value: parseEther("2") });
      await launchpad.connect(bob).join(launchId, { value: parseEther("3") });
      
      await launchpad.launch(launchId);
    });

    it("should distribute tokens pro-rata", async function () {
      const info = await launchpad.getLaunchInfo(launchId);
      const tokenAddress = info.token;
      const token = await ethers.getContractAt("MockClankerToken", tokenAddress);
      
      await launchpad.claim(launchId);
      
      const aliceBalance = await token.balanceOf(alice.address);
      const bobBalance = await token.balanceOf(bob.address);
      
      // Both should have tokens
      expect(aliceBalance).to.be.gt(0);
      expect(bobBalance).to.be.gt(0);
      
      // Bob should have 1.5x more (60% vs 40%)
      // Allow some tolerance for rounding
      const ratio = bobBalance * 10000n / aliceBalance;
      expect(ratio).to.be.closeTo(15000n, 100n); // ~1.5x
    });

    it("should revert if not launched", async function () {
      // Create new launch, don't launch it
      const now = await time.latest();
      await launchpad.create("New", "NEW", "", parseEther("1"), now + ONE_DAY);
      await launchpad.connect(alice).join(1, { value: parseEther("1") });
      
      await expect(launchpad.claim(1)).to.be.revertedWith("not launched");
    });
  });

  describe("Fee Claiming", function () {
    let launchId: number;
    let tokenAddress: string;

    beforeEach(async function () {
      const now = await time.latest();
      
      await launchpad.create("Test", "TEST", "", parseEther("5"), now + ONE_DAY);
      launchId = 0;
      
      await launchpad.connect(alice).join(launchId, { value: parseEther("2") });
      await launchpad.connect(bob).join(launchId, { value: parseEther("3") });
      
      await launchpad.launch(launchId);
      
      const info = await launchpad.getLaunchInfo(launchId);
      tokenAddress = info.token;
    });

    it("should claim and distribute WETH fees", async function () {
      // Add WETH fees to the mock fee locker
      await weth.deposit({ value: parseEther("1") });
      await weth.transfer(await feeLocker.getAddress(), parseEther("1"));
      await feeLocker.addFees(await launchpad.getAddress(), tokenAddress, parseEther("1"), 0);
      
      const aliceBefore = await weth.balanceOf(alice.address);
      const bobBefore = await weth.balanceOf(bob.address);
      
      await launchpad.claimFees(launchId);
      
      const aliceAfter = await weth.balanceOf(alice.address);
      const bobAfter = await weth.balanceOf(bob.address);
      
      // Alice: 40%, Bob: 60% of 1 ETH
      expect(aliceAfter - aliceBefore).to.equal(parseEther("0.4"));
      expect(bobAfter - bobBefore).to.equal(parseEther("0.6"));
    });

    it("should claim and distribute token fees", async function () {
      const token = await ethers.getContractAt("MockClankerToken", tokenAddress);
      
      // First claim initial tokens
      await launchpad.claim(launchId);
      
      const aliceInitial = await token.balanceOf(alice.address);
      const bobInitial = await token.balanceOf(bob.address);
      
      // Add token fees to fee locker
      // Need to mint more tokens to fee locker
      const tokenFactory = await ethers.getContractFactory("MockERC20");
      const feeTokens = parseEther("1000");
      
      // Transfer some tokens to fee locker for fees
      // This simulates fees accumulated from trading
      await token.connect(alice).transfer(await feeLocker.getAddress(), parseEther("100"));
      await feeLocker.addFees(await launchpad.getAddress(), tokenAddress, 0, parseEther("100"));
      
      await launchpad.claimFees(launchId);
      
      const aliceAfter = await token.balanceOf(alice.address);
      const bobAfter = await token.balanceOf(bob.address);
      
      // Should have received fee share
      expect(aliceAfter).to.be.gt(aliceInitial - parseEther("100")); // Account for transfer
    });

    it("should show available fees", async function () {
      await weth.deposit({ value: parseEther("2") });
      await weth.transfer(await feeLocker.getAddress(), parseEther("2"));
      await feeLocker.addFees(await launchpad.getAddress(), tokenAddress, parseEther("2"), parseEther("500"));
      
      const [wethFees, tokenFees] = await launchpad.availableFees(launchId);
      
      expect(wethFees).to.equal(parseEther("2"));
      expect(tokenFees).to.equal(parseEther("500"));
    });

    it("should revert if not launched", async function () {
      const now = await time.latest();
      await launchpad.create("New", "NEW", "", parseEther("1"), now + ONE_DAY);
      await launchpad.connect(alice).join(1, { value: parseEther("1") });
      
      await expect(launchpad.claimFees(1)).to.be.revertedWith("not launched");
    });
  });

  describe("Withdraw (Expired)", function () {
    let launchId: number;
    let deadline: number;

    beforeEach(async function () {
      const now = await time.latest();
      deadline = now + ONE_DAY;
      
      await launchpad.create("Test", "TEST", "", parseEther("100"), deadline); // High threshold
      launchId = 0;
      
      await launchpad.connect(alice).join(launchId, { value: parseEther("2") });
      await launchpad.connect(bob).join(launchId, { value: parseEther("3") });
    });

    it("should refund contributors when expired", async function () {
      await time.increaseTo(deadline + 1);
      
      const aliceBefore = await ethers.provider.getBalance(alice.address);
      const bobBefore = await ethers.provider.getBalance(bob.address);
      
      await launchpad.withdraw(launchId);
      
      const aliceAfter = await ethers.provider.getBalance(alice.address);
      const bobAfter = await ethers.provider.getBalance(bob.address);
      
      expect(aliceAfter - aliceBefore).to.equal(parseEther("2"));
      expect(bobAfter - bobBefore).to.equal(parseEther("3"));
    });

    it("should revert if deadline not passed", async function () {
      await expect(launchpad.withdraw(launchId)).to.be.revertedWith("cannot");
    });

    it("should revert if already launched", async function () {
      // Create launch that will succeed
      const now = await time.latest();
      await launchpad.create("Low", "LOW", "", parseEther("1"), now + ONE_DAY);
      await launchpad.connect(alice).join(1, { value: parseEther("1") });
      await launchpad.launch(1);
      
      await time.increaseTo(now + ONE_DAY + 1);
      
      await expect(launchpad.withdraw(1)).to.be.revertedWith("cannot");
    });
  });

  describe("Multiple Launches", function () {
    it("should track multiple launches independently", async function () {
      const now = await time.latest();
      
      await launchpad.create("Token A", "TKNA", "", parseEther("1"), now + ONE_DAY);
      await launchpad.create("Token B", "TKNB", "", parseEther("2"), now + ONE_DAY);
      await launchpad.create("Token C", "TKNC", "", parseEther("3"), now + ONE_DAY);
      
      expect(await launchpad.count()).to.equal(3);
      
      // Fund differently
      await launchpad.connect(alice).join(0, { value: parseEther("1") });
      await launchpad.connect(bob).join(1, { value: parseEther("2") });
      await launchpad.connect(charlie).join(2, { value: parseEther("3") });
      
      // Launch all
      await launchpad.launch(0);
      await launchpad.launch(1);
      await launchpad.launch(2);
      
      // Each should have different token
      const info0 = await launchpad.getLaunchInfo(0);
      const info1 = await launchpad.getLaunchInfo(1);
      const info2 = await launchpad.getLaunchInfo(2);
      
      expect(info0.token).to.not.equal(info1.token);
      expect(info1.token).to.not.equal(info2.token);
      expect(info0.token).to.not.equal(info2.token);
    });
  });
});
