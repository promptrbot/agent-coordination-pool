// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockWETH.sol";
import "../../contracts/mocks/LaunchpadTestable.sol";
import "../../contracts/mocks/MockClanker.sol";

/// @title LaunchpadComprehensiveTest - Every possible edge case
contract LaunchpadComprehensiveTest is Test {
    ACP public acp;
    LaunchpadTestable public launchpad;
    MockWETH public weth;
    MockClanker public clanker;
    MockClankerFeeLocker public feeLocker;
    
    address public alice = address(2);
    address public bob = address(3);
    address public creator = address(4);
    
    uint256 constant ONE_DAY = 86400;
    
    event LaunchCreated(uint256 indexed launchId, string name, string symbol, uint256 threshold);
    event Joined(uint256 indexed launchId, address indexed contributor, uint256 amount);
    event Launched(uint256 indexed launchId, address token, uint256 ethRaised);
    
    function setUp() public {
        acp = new ACP();
        weth = new MockWETH();
        clanker = new MockClanker();
        feeLocker = new MockClankerFeeLocker(address(weth));
        
        launchpad = new LaunchpadTestable(
            address(acp),
            address(clanker),
            address(weth),
            address(feeLocker)
        );
        
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(creator, 100 ether);
    }
    
    // ============================================================
    //                    CREATE VALIDATION
    // ============================================================
    
    function test_Create_RevertEmptyName() public {
        vm.expectRevert("empty");
        launchpad.create("", "SYM", "", 1 ether, block.timestamp + ONE_DAY);
    }
    
    function test_Create_RevertEmptySymbol() public {
        vm.expectRevert("empty");
        launchpad.create("Name", "", "", 1 ether, block.timestamp + ONE_DAY);
    }
    
    function test_Create_RevertZeroThreshold() public {
        vm.expectRevert("invalid");
        launchpad.create("Name", "SYM", "", 0, block.timestamp + ONE_DAY);
    }
    
    function test_Create_RevertPastDeadline() public {
        vm.expectRevert("invalid");
        launchpad.create("Name", "SYM", "", 1 ether, block.timestamp - 1);
    }
    
    function test_Create_RevertCurrentTimestamp() public {
        vm.expectRevert("invalid");
        launchpad.create("Name", "SYM", "", 1 ether, block.timestamp);
    }
    
    function test_Create_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit LaunchCreated(0, "TestToken", "TEST", 5 ether);
        
        launchpad.create("TestToken", "TEST", "", 5 ether, block.timestamp + ONE_DAY);
    }
    
    function test_Create_IncreasesCount() public {
        assertEq(launchpad.count(), 0);
        
        launchpad.create("Token1", "TK1", "", 1 ether, block.timestamp + ONE_DAY);
        assertEq(launchpad.count(), 1);
        
        launchpad.create("Token2", "TK2", "", 2 ether, block.timestamp + ONE_DAY);
        assertEq(launchpad.count(), 2);
    }
    
    function test_Create_RecordsCreator() public {
        vm.prank(creator);
        uint256 launchId = launchpad.create("Test", "TST", "", 1 ether, block.timestamp + ONE_DAY);
        
        (
            uint256 poolId,
            string memory name,
            string memory symbol,
            string memory image,
            uint256 threshold,
            uint256 deadline,
            address token,
            address launchCreator,
            LaunchpadTestable.Status status
        ) = launchpad.launches(launchId);
        
        assertEq(launchCreator, creator);
    }
    
    function test_Create_WithImage() public {
        uint256 launchId = launchpad.create("Test", "TST", "https://example.com/image.png", 1 ether, block.timestamp + ONE_DAY);
        
        (,,, string memory image,,,,,) = launchpad.launches(launchId);
        assertEq(image, "https://example.com/image.png");
    }
    
    function test_Create_MinimalDeadline() public {
        // Deadline just 1 second in future
        uint256 launchId = launchpad.create("Test", "TST", "", 1 ether, block.timestamp + 1);
        assertEq(launchId, 0);
    }
    
    // ============================================================
    //                    JOIN VALIDATION
    // ============================================================
    
    function test_Join_EmitsEvent() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Joined(launchId, alice, 2 ether);
        launchpad.join{value: 2 ether}(launchId);
    }
    
    function test_Join_AtExactDeadline() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, deadline);
        
        vm.warp(deadline);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        assertEq(launchpad.getContribution(launchId, alice), 1 ether);
    }
    
    function test_Join_OneSecondAfterDeadline() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, deadline);
        
        vm.warp(deadline + 1);
        
        vm.prank(alice);
        vm.expectRevert("closed");
        launchpad.join{value: 1 ether}(launchId);
    }
    
    function test_Join_SameUserMultipleTimes() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 10 ether, block.timestamp + ONE_DAY);
        
        vm.startPrank(alice);
        launchpad.join{value: 1 ether}(launchId);
        launchpad.join{value: 2 ether}(launchId);
        launchpad.join{value: 3 ether}(launchId);
        vm.stopPrank();
        
        assertEq(launchpad.getContribution(launchId, alice), 6 ether);
    }
    
    function test_Join_ZeroValue() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        vm.expectRevert("no value");
        launchpad.join{value: 0}(launchId);
    }
    
    function test_Join_AfterLaunched() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 1 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        launchpad.launch(launchId);
        
        vm.prank(bob);
        vm.expectRevert("closed");
        launchpad.join{value: 1 ether}(launchId);
    }
    
    // ============================================================
    //                    LAUNCH VALIDATION
    // ============================================================
    
    function test_Launch_EmitsEvent() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        vm.expectEmit(true, false, false, false);
        emit Launched(launchId, address(0), 5 ether);
        launchpad.launch(launchId);
    }
    
    function test_Launch_ThresholdExactlyMet() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        launchpad.launch(launchId);
        
        (,,,,, LaunchpadTestable.Status status,,) = launchpad.getLaunchInfo(launchId);
        assertEq(uint256(status), 1); // Launched
    }
    
    function test_Launch_ThresholdExceeded() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 10 ether}(launchId);
        
        launchpad.launch(launchId);
        
        (,,,,,, uint256 total,) = launchpad.getLaunchInfo(launchId);
        assertEq(total, 10 ether);
    }
    
    function test_Launch_SetsToken() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        launchpad.launch(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        assertTrue(token != address(0));
    }
    
    function test_Launch_ThresholdNotMet() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 100 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        vm.expectRevert("threshold not met");
        launchpad.launch(launchId);
    }
    
    function test_Launch_NoContributors() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.expectRevert("threshold not met");
        launchpad.launch(launchId);
    }
    
    // ============================================================
    //                    CLAIM & WITHDRAW
    // ============================================================
    
    function test_Claim_DistributesTokens() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 2 ether}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: 3 ether}(launchId);
        
        launchpad.launch(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        
        launchpad.claim(launchId);
        
        // Both should have tokens
        assertTrue(IERC20(token).balanceOf(alice) > 0);
        assertTrue(IERC20(token).balanceOf(bob) > 0);
    }
    
    function test_Claim_Twice() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        launchpad.launch(launchId);
        
        launchpad.claim(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        uint256 aliceBalance = IERC20(token).balanceOf(alice);
        
        // Second claim - nothing left
        launchpad.claim(launchId);
        
        assertEq(IERC20(token).balanceOf(alice), aliceBalance);
    }
    
    function test_Withdraw_SetsStatusExpired() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        uint256 launchId = launchpad.create("Test", "TST", "", 100 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        vm.warp(deadline + 1);
        launchpad.withdraw(launchId);
        
        (,,,,, LaunchpadTestable.Status status,,) = launchpad.getLaunchInfo(launchId);
        assertEq(uint256(status), 2); // Expired
    }
    
    function test_Withdraw_RefundsContributors() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        uint256 launchId = launchpad.create("Test", "TST", "", 100 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: 3 ether}(launchId);
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.warp(deadline + 1);
        launchpad.withdraw(launchId);
        
        assertEq(alice.balance - aliceBefore, 5 ether);
        assertEq(bob.balance - bobBefore, 3 ether);
    }
    
    function test_Withdraw_BeforeDeadline() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        uint256 launchId = launchpad.create("Test", "TST", "", 100 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        vm.expectRevert("cannot");
        launchpad.withdraw(launchId);
    }
    
    function test_Withdraw_AfterExpired() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        uint256 launchId = launchpad.create("Test", "TST", "", 100 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        vm.warp(deadline + 1);
        launchpad.withdraw(launchId);
        
        vm.expectRevert("cannot");
        launchpad.withdraw(launchId);
    }
    
    // ============================================================
    //                    CLAIM FEES
    // ============================================================
    
    function test_ClaimFees_NoFees() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        launchpad.launch(launchId);
        launchpad.claim(launchId);
        
        uint256 aliceWethBefore = weth.balanceOf(alice);
        
        launchpad.claimFees(launchId);
        
        // No change
        assertEq(weth.balanceOf(alice), aliceWethBefore);
    }
    
    function test_ClaimFees_BeforeLaunch() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        vm.expectRevert("not launched");
        launchpad.claimFees(launchId);
    }
    
    function test_AvailableFees_NotLaunched() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        (uint256 wethFees, uint256 tokenFees) = launchpad.availableFees(launchId);
        
        assertEq(wethFees, 0);
        assertEq(tokenFees, 0);
    }
    
    function test_AvailableFees_WithFees() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        launchpad.launch(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        
        // Simulate fees
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();
        weth.transfer(address(feeLocker), 10 ether);
        feeLocker.addFees(address(launchpad), token, 10 ether, 0);
        
        (uint256 wethFees, uint256 tokenFees) = launchpad.availableFees(launchId);
        
        assertEq(wethFees, 10 ether);
        assertEq(tokenFees, 0);
    }
    
    // ============================================================
    //                    VIEW FUNCTIONS
    // ============================================================
    
    function test_GetLaunchInfo_AllFields() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        
        vm.prank(creator);
        uint256 launchId = launchpad.create("TestToken", "TEST", "https://img.com", 5 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 3 ether}(launchId);
        
        (
            string memory name,
            string memory symbol,
            uint256 threshold,
            uint256 dl,
            address token,
            LaunchpadTestable.Status status,
            uint256 total,
            uint256 count
        ) = launchpad.getLaunchInfo(launchId);
        
        assertEq(name, "TestToken");
        assertEq(symbol, "TEST");
        assertEq(threshold, 5 ether);
        assertEq(dl, deadline);
        assertEq(token, address(0)); // Not launched yet
        assertEq(uint256(status), 0); // Funding
        assertEq(total, 3 ether);
        assertEq(count, 1);
    }
    
    function test_GetContribution_NonContributor() public {
        uint256 launchId = launchpad.create("Test", "TST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        assertEq(launchpad.getContribution(launchId, bob), 0);
    }
    
    function test_LaunchesArray_DirectAccess() public {
        vm.prank(creator);
        launchpad.create("TestToken", "TEST", "https://img.com", 5 ether, block.timestamp + ONE_DAY);
        
        (
            uint256 poolId,
            string memory name,
            string memory symbol,
            string memory image,
            uint256 threshold,
            uint256 deadline,
            address token,
            address launchCreator,
            LaunchpadTestable.Status status
        ) = launchpad.launches(0);
        
        assertEq(poolId, 0);
        assertEq(name, "TestToken");
        assertEq(symbol, "TEST");
        assertEq(image, "https://img.com");
        assertEq(threshold, 5 ether);
        assertGt(deadline, block.timestamp);
        assertEq(token, address(0));
        assertEq(launchCreator, creator);
        assertEq(uint256(status), 0);
    }
    
    // ============================================================
    //                    INVALID LAUNCH IDS
    // ============================================================
    
    function test_Join_InvalidLaunchId() public {
        vm.prank(alice);
        vm.expectRevert();
        launchpad.join{value: 1 ether}(999);
    }
    
    function test_Launch_InvalidLaunchId() public {
        vm.expectRevert();
        launchpad.launch(999);
    }
    
    function test_GetLaunchInfo_InvalidLaunchId() public {
        vm.expectRevert();
        launchpad.getLaunchInfo(999);
    }
    
    // ============================================================
    //                    RECEIVE FUNCTION
    // ============================================================
    
    function test_Receive() public {
        (bool ok,) = address(launchpad).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(launchpad).balance, 1 ether);
    }
    
    // ============================================================
    //                    UNICODE / SPECIAL CHARACTERS
    // ============================================================
    
    function test_Create_UnicodeNameSymbol() public {
        uint256 launchId = launchpad.create(
            unicode"测试代币",
            unicode"测试",
            "",
            1 ether,
            block.timestamp + ONE_DAY
        );
        
        (string memory name, string memory symbol,,,,,,) = launchpad.getLaunchInfo(launchId);
        assertEq(name, unicode"测试代币");
        assertEq(symbol, unicode"测试");
    }
    
    function test_Create_EmojiName() public {
        uint256 launchId = launchpad.create(
            unicode"🚀 Moon Token 🌕",
            "MOON",
            "",
            1 ether,
            block.timestamp + ONE_DAY
        );
        
        (string memory name,,,,,,, ) = launchpad.getLaunchInfo(launchId);
        assertEq(name, unicode"🚀 Moon Token 🌕");
    }
    
    function test_Create_LongName() public {
        string memory longName = "This is a very long token name that might be used by someone who really likes descriptive names for their tokens and wants everyone to know exactly what this token is about";
        
        uint256 launchId = launchpad.create(longName, "LONG", "", 1 ether, block.timestamp + ONE_DAY);
        
        (string memory name,,,,,,, ) = launchpad.getLaunchInfo(launchId);
        assertEq(name, longName);
    }
}
