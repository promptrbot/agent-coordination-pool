// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockWETH.sol";
import "../../contracts/mocks/LaunchpadTestable.sol";
import "../../contracts/mocks/MockClanker.sol";

contract LaunchpadE2ETest is Test {
    ACP public acp;
    LaunchpadTestable public launchpad;
    MockWETH public weth;
    MockClanker public clanker;
    MockClankerFeeLocker public feeLocker;
    
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    
    uint256 constant ONE_DAY = 86400;
    
    function setUp() public {
        // Deploy infrastructure
        acp = new ACP();
        weth = new MockWETH();
        clanker = new MockClanker();
        feeLocker = new MockClankerFeeLocker(address(weth));
        
        // Deploy Launchpad with mocks
        launchpad = new LaunchpadTestable(
            address(acp),
            address(clanker),
            address(weth),
            address(feeLocker)
        );
        
        // Fund users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    // ============================================================
    //                     E2E: HAPPY PATH
    // ============================================================
    
    function test_E2E_SuccessfulLaunch() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        
        // 1. Create launch
        uint256 launchId = launchpad.create(
            "Community Token",
            "COMM",
            "https://example.com/logo.png",
            5 ether,
            deadline
        );
        
        // 2. Contributors join
        vm.prank(alice);
        launchpad.join{value: 2 ether}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: 3 ether}(launchId);
        
        // Verify state
        (string memory name, string memory symbol, uint256 threshold,
         uint256 dl, address token, LaunchpadTestable.Status status,
         uint256 total, uint256 count) = launchpad.getLaunchInfo(launchId);
         
        assertEq(name, "Community Token");
        assertEq(symbol, "COMM");
        assertEq(threshold, 5 ether);
        assertEq(dl, deadline);
        assertEq(token, address(0));
        assertEq(uint256(status), 0); // Funding
        assertEq(total, 5 ether);
        assertEq(count, 2);
        
        // 3. Launch
        launchpad.launch(launchId);
        
        // Get token address
        (,,,, token, status,,) = launchpad.getLaunchInfo(launchId);
        assertEq(uint256(status), 1); // Launched
        assertTrue(token != address(0));
        
        // 4. Claim tokens
        IERC20 launchedToken = IERC20(token);
        uint256 acpBalance = launchedToken.balanceOf(address(acp));
        assertGt(acpBalance, 0);
        
        launchpad.claim(launchId);
        
        // Check token distribution: Alice 40%, Bob 60%
        uint256 aliceTokens = launchedToken.balanceOf(alice);
        uint256 bobTokens = launchedToken.balanceOf(bob);
        
        assertGt(aliceTokens, 0);
        assertGt(bobTokens, 0);
        
        // Bob should have 1.5x Alice's tokens
        assertApproxEqRel(bobTokens * 2, aliceTokens * 3, 0.01e18);
    }
    
    function test_E2E_ManyContributors() public {
        uint256 launchId = launchpad.create(
            "Many Token",
            "MANY",
            "",
            10 ether,
            block.timestamp + ONE_DAY
        );
        
        // 20 contributors
        for (uint i = 10; i < 30; i++) {
            address contributor = address(uint160(i));
            vm.deal(contributor, 1 ether);
            vm.prank(contributor);
            launchpad.join{value: 0.5 ether}(launchId);
        }
        
        launchpad.launch(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        
        launchpad.claim(launchId);
        
        // All contributors should have tokens
        IERC20 launchedToken = IERC20(token);
        for (uint i = 10; i < 30; i++) {
            address contributor = address(uint160(i));
            assertGt(launchedToken.balanceOf(contributor), 0);
        }
    }
    
    // ============================================================
    //                    E2E: FEE DISTRIBUTION
    // ============================================================
    
    function test_E2E_FeeClaiming() public {
        // Create and launch
        uint256 launchId = launchpad.create("Fee Token", "FEE", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 2 ether}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: 3 ether}(launchId);
        
        launchpad.launch(launchId);
        launchpad.claim(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        
        // Simulate fee accumulation
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();
        weth.transfer(address(feeLocker), 10 ether);
        feeLocker.addFees(address(launchpad), token, 10 ether, 0);
        
        // Check available fees
        (uint256 wethFees, uint256 tokenFees) = launchpad.availableFees(launchId);
        assertEq(wethFees, 10 ether);
        assertEq(tokenFees, 0);
        
        // Claim fees
        uint256 aliceWethBefore = weth.balanceOf(alice);
        uint256 bobWethBefore = weth.balanceOf(bob);
        
        launchpad.claimFees(launchId);
        
        // Alice: 40% = 4 WETH, Bob: 60% = 6 WETH
        assertEq(weth.balanceOf(alice) - aliceWethBefore, 4 ether);
        assertEq(weth.balanceOf(bob) - bobWethBefore, 6 ether);
    }
    
    function test_E2E_MultipleFeeClaims() public {
        uint256 launchId = launchpad.create("Multi Fee", "MFEE", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        launchpad.launch(launchId);
        launchpad.claim(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        
        // First fee batch
        vm.deal(address(this), 20 ether);
        weth.deposit{value: 20 ether}();
        weth.transfer(address(feeLocker), 5 ether);
        feeLocker.addFees(address(launchpad), token, 5 ether, 0);
        
        launchpad.claimFees(launchId);
        assertEq(weth.balanceOf(alice), 5 ether);
        
        // Second fee batch
        weth.transfer(address(feeLocker), 10 ether);
        feeLocker.addFees(address(launchpad), token, 10 ether, 0);
        
        launchpad.claimFees(launchId);
        assertEq(weth.balanceOf(alice), 15 ether);
    }
    
    // ============================================================
    //                    E2E: REFUND PATH
    // ============================================================
    
    function test_E2E_ThresholdNotMet_Refund() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        
        uint256 launchId = launchpad.create(
            "Failed Token",
            "FAIL",
            "",
            100 ether,  // High threshold
            deadline
        );
        
        vm.prank(alice);
        launchpad.join{value: 5 ether}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: 3 ether}(launchId);
        
        // Can't launch (threshold not met)
        vm.expectRevert("threshold not met");
        launchpad.launch(launchId);
        
        // Wait for deadline
        vm.warp(deadline + 1);
        
        // Withdraw and refund
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        launchpad.withdraw(launchId);
        
        assertEq(alice.balance - aliceBefore, 5 ether);
        assertEq(bob.balance - bobBefore, 3 ether);
        
        // Status should be expired
        (,,,,, LaunchpadTestable.Status status,,) = launchpad.getLaunchInfo(launchId);
        assertEq(uint256(status), 2); // Expired
    }
    
    // ============================================================
    //                    VALIDATION TESTS
    // ============================================================
    
    function test_CantCreateWithEmptyName() public {
        vm.expectRevert("empty");
        launchpad.create("", "SYM", "", 1 ether, block.timestamp + ONE_DAY);
    }
    
    function test_CantCreateWithEmptySymbol() public {
        vm.expectRevert("empty");
        launchpad.create("Name", "", "", 1 ether, block.timestamp + ONE_DAY);
    }
    
    function test_CantCreateWithZeroThreshold() public {
        vm.expectRevert("invalid");
        launchpad.create("Name", "SYM", "", 0, block.timestamp + ONE_DAY);
    }
    
    function test_CantCreateWithPastDeadline() public {
        vm.expectRevert("invalid");
        launchpad.create("Name", "SYM", "", 1 ether, block.timestamp - 1);
    }
    
    function test_CantJoinAfterDeadline() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        
        uint256 launchId = launchpad.create("Test", "TEST", "", 5 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 2 ether}(launchId);
        
        vm.warp(deadline + 1);
        
        vm.prank(bob);
        vm.expectRevert("closed");
        launchpad.join{value: 3 ether}(launchId);
    }
    
    function test_CantJoinWithZeroValue() public {
        uint256 launchId = launchpad.create("Test", "TEST", "", 5 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        vm.expectRevert("no value");
        launchpad.join{value: 0}(launchId);
    }
    
    // ============================================================
    //                    STATE TRANSITIONS
    // ============================================================
    
    function test_CantLaunchTwice() public {
        uint256 launchId = launchpad.create("Test", "TEST", "", 1 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        launchpad.launch(launchId);
        
        vm.expectRevert("not funding");
        launchpad.launch(launchId);
    }
    
    function test_CantClaimBeforeLaunch() public {
        uint256 launchId = launchpad.create("Test", "TEST", "", 1 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        vm.expectRevert("not launched");
        launchpad.claim(launchId);
    }
    
    function test_CantWithdrawAfterLaunch() public {
        uint256 launchId = launchpad.create("Test", "TEST", "", 1 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        launchpad.launch(launchId);
        
        vm.warp(block.timestamp + ONE_DAY + 1);
        
        vm.expectRevert("cannot");
        launchpad.withdraw(launchId);
    }
    
    function test_CantWithdrawBeforeDeadline() public {
        uint256 deadline = block.timestamp + ONE_DAY;
        
        uint256 launchId = launchpad.create("Test", "TEST", "", 100 ether, deadline);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        vm.expectRevert("cannot");
        launchpad.withdraw(launchId);
    }
    
    function test_CantClaimFeesBeforeLaunch() public {
        uint256 launchId = launchpad.create("Test", "TEST", "", 1 ether, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: 1 ether}(launchId);
        
        vm.expectRevert("not launched");
        launchpad.claimFees(launchId);
    }
    
    // ============================================================
    //                    MULTIPLE LAUNCHES
    // ============================================================
    
    function test_MultipleLaunches() public {
        // Create 3 launches
        uint256[] memory launchIds = new uint256[](3);
        
        for (uint i = 0; i < 3; i++) {
            launchIds[i] = launchpad.create(
                string(abi.encodePacked("Token", vm.toString(i))),
                string(abi.encodePacked("TKN", vm.toString(i))),
                "",
                1 ether,
                block.timestamp + ONE_DAY
            );
            
            vm.prank(alice);
            launchpad.join{value: 1 ether}(launchIds[i]);
        }
        
        assertEq(launchpad.count(), 3);
        
        // Launch all
        for (uint i = 0; i < 3; i++) {
            launchpad.launch(launchIds[i]);
        }
        
        // Each should have different token
        (,,,, address token0,,,) = launchpad.getLaunchInfo(launchIds[0]);
        (,,,, address token1,,,) = launchpad.getLaunchInfo(launchIds[1]);
        (,,,, address token2,,,) = launchpad.getLaunchInfo(launchIds[2]);
        
        assertTrue(token0 != token1);
        assertTrue(token1 != token2);
        assertTrue(token0 != token2);
    }
    
    // ============================================================
    //                      FUZZ TESTS
    // ============================================================
    
    function testFuzz_ContributionsPreserved(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 >= 0.01 ether && amount2 >= 0.01 ether);
        vm.assume(uint256(amount1) + uint256(amount2) <= 50 ether);
        
        uint256 threshold = uint256(amount1) + uint256(amount2);
        
        uint256 launchId = launchpad.create(
            "Fuzz Token",
            "FUZZ",
            "",
            threshold,
            block.timestamp + ONE_DAY
        );
        
        vm.prank(alice);
        launchpad.join{value: amount1}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: amount2}(launchId);
        
        assertEq(launchpad.getContribution(launchId, alice), amount1);
        assertEq(launchpad.getContribution(launchId, bob), amount2);
    }
    
    function testFuzz_TokenDistributionProportional(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 >= 0.1 ether && amount2 >= 0.1 ether);
        vm.assume(uint256(amount1) + uint256(amount2) <= 50 ether);
        
        uint256 threshold = uint256(amount1) + uint256(amount2);
        
        uint256 launchId = launchpad.create("Fuzz", "FUZ", "", threshold, block.timestamp + ONE_DAY);
        
        vm.prank(alice);
        launchpad.join{value: amount1}(launchId);
        
        vm.prank(bob);
        launchpad.join{value: amount2}(launchId);
        
        launchpad.launch(launchId);
        
        (,,,, address token,,,) = launchpad.getLaunchInfo(launchId);
        
        launchpad.claim(launchId);
        
        IERC20 launchedToken = IERC20(token);
        uint256 aliceTokens = launchedToken.balanceOf(alice);
        uint256 bobTokens = launchedToken.balanceOf(bob);
        
        // Check proportionality
        uint256 cross1 = aliceTokens * uint256(amount2);
        uint256 cross2 = bobTokens * uint256(amount1);
        
        uint256 tolerance = (cross1 > cross2 ? cross1 : cross2) / 1000; // 0.1%
        uint256 diff = cross1 > cross2 ? cross1 - cross2 : cross2 - cross1;
        assertLe(diff, tolerance + 1);
    }
}
