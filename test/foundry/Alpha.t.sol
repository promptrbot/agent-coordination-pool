// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockWETH.sol";
import "../../contracts/mocks/AlphaTestable.sol";
import "../../contracts/mocks/MockAerodrome.sol";

contract AlphaE2ETest is Test {
    ACP public acp;
    AlphaTestable public alpha;
    MockWETH public weth;
    MockERC20 public targetToken;
    MockAerodrome public router;
    
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    
    uint256 constant ONE_HOUR = 3600;
    uint256 constant ONE_DAY = 86400;
    
    function setUp() public {
        // Deploy infrastructure
        acp = new ACP();
        weth = new MockWETH();
        targetToken = new MockERC20("Target Token", "TGT", 18);
        router = new MockAerodrome();
        
        // Deploy Alpha with mocks
        alpha = new AlphaTestable(address(acp), address(router), address(weth));
        
        // Fund router for swaps
        targetToken.mint(address(router), 10_000_000 ether);
        vm.deal(address(this), 10000 ether);
        weth.deposit{value: 10000 ether}();
        weth.transfer(address(router), 10000 ether);
        
        // Set exchange rates: 1 WETH = 1000 TGT, 1000 TGT = 1.2 WETH (20% profit)
        router.setExchangeRate(address(targetToken), 100000); // 10x
        router.setExchangeRate(address(weth), 1200); // 0.12x
        
        // Fund users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    // ============================================================
    //                     E2E: HAPPY PATH
    // ============================================================
    
    function test_E2E_SuccessfulTrade() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        uint256 deadline = buyTime - 60;
        
        // 1. Create trade
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,      // threshold
            buyTime,
            sellTime,
            deadline,
            200
        );
        
        // 2. Contributors join
        vm.prank(alice);
        alpha.join{value: 2 ether}(tradeId);
        
        vm.prank(bob);
        alpha.join{value: 3 ether}(tradeId);
        
        // Verify state
        (,uint256 threshold,,,,, AlphaTestable.Status status, uint256 total, uint256 count) = alpha.getTradeInfo(tradeId);
        assertEq(threshold, 5 ether);
        assertEq(total, 5 ether);
        assertEq(count, 2);
        assertEq(uint256(status), 0); // Funding
        
        // 3. Execute buy
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        (,,,,,, status,,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 1); // Bought
        
        // 4. Execute sell
        vm.warp(sellTime);
        alpha.executeSell(tradeId);
        
        (,,,,,, status,,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 2); // Sold
        
        // 5. Claim
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        alpha.claim(tradeId);
        
        // Both should have profit (20% based on mock rates)
        assertGt(alice.balance, aliceBefore);
        assertGt(bob.balance, bobBefore);
        
        // Check proportionality: Alice 40%, Bob 60%
        uint256 aliceProfit = alice.balance - aliceBefore;
        uint256 bobProfit = bob.balance - bobBefore;
        
        // Bob should have 1.5x Alice's share
        assertApproxEqRel(bobProfit * 2, aliceProfit * 3, 0.01e18);
    }
    
    function test_E2E_ManyContributors() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            10 ether,
            buyTime,
            sellTime,
            buyTime - 60,
            200
        );
        
        // 20 contributors
        uint256 totalContributed;
        for (uint i = 10; i < 30; i++) {
            address contributor = address(uint160(i));
            vm.deal(contributor, 1 ether);
            vm.prank(contributor);
            alpha.join{value: 0.5 ether}(tradeId);
            totalContributed += 0.5 ether;
        }
        
        assertEq(totalContributed, 10 ether);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.warp(sellTime);
        alpha.executeSell(tradeId);
        
        // All should be able to claim
        alpha.claim(tradeId);
    }
    
    // ============================================================
    //                    E2E: REFUND PATH
    // ============================================================
    
    function test_E2E_ThresholdNotMet_Refund() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 deadline = buyTime - 60;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            100 ether,     // High threshold
            buyTime,
            block.timestamp + ONE_DAY,
            deadline,
            200
        );
        
        // Only partial funding
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.prank(bob);
        alpha.join{value: 3 ether}(tradeId);
        
        // Wait for buyTime (which is after deadline)
        vm.warp(buyTime);
        
        // Can't buy (threshold not met)
        vm.expectRevert("threshold not met");
        alpha.executeBuy(tradeId);
        
        // Withdraw and refund
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        alpha.withdraw(tradeId);
        
        assertEq(alice.balance - aliceBefore, 5 ether);
        assertEq(bob.balance - bobBefore, 3 ether);
    }
    
    // ============================================================
    //                    E2E: LOSS SCENARIO
    // ============================================================
    
    function test_E2E_TradeWithLoss() public {
        // Set exchange rate for loss: sell gets less back
        router.setExchangeRate(address(targetToken), 100000); // 10x on buy
        router.setExchangeRate(address(weth), 500); // 0.05x on sell (50% loss)
        
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            buyTime,
            sellTime,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.warp(sellTime);
        alpha.executeSell(tradeId);
        
        uint256 aliceBefore = alice.balance;
        alpha.claim(tradeId);
        uint256 aliceAfter = alice.balance;
        
        // Alice should get less than she put in
        assertLt(aliceAfter - aliceBefore, 5 ether);
    }
    
    // ============================================================
    //                    TIMING TESTS
    // ============================================================
    
    function test_CantJoinAfterDeadline() public {
        uint256 deadline = block.timestamp + ONE_HOUR;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            deadline + 60,
            block.timestamp + ONE_DAY,
            deadline,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 2 ether}(tradeId);
        
        vm.warp(deadline + 1);
        
        vm.prank(bob);
        vm.expectRevert("closed");
        alpha.join{value: 3 ether}(tradeId);
    }
    
    function test_CantBuyBeforeBuyTime() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            buyTime,
            block.timestamp + ONE_DAY,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.expectRevert("too early");
        alpha.executeBuy(tradeId);
    }
    
    function test_CantSellBeforeSellTime() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            buyTime,
            sellTime,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.expectRevert("too early");
        alpha.executeSell(tradeId);
    }
    
    // ============================================================
    //                    STATE TRANSITIONS
    // ============================================================
    
    function test_CantBuyTwice() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            buyTime,
            block.timestamp + ONE_DAY,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.expectRevert("not funding");
        alpha.executeBuy(tradeId);
    }
    
    function test_CantSellWithoutBuy() public {
        uint256 sellTime = block.timestamp + ONE_DAY;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            block.timestamp + ONE_HOUR,
            sellTime,
            block.timestamp + ONE_HOUR - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(sellTime);
        vm.expectRevert("not bought");
        alpha.executeSell(tradeId);
    }
    
    function test_CantClaimWithoutSell() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            buyTime,
            block.timestamp + ONE_DAY,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.expectRevert("not sold");
        alpha.claim(tradeId);
    }
    
    function test_CantWithdrawAfterBuy() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            5 ether,
            buyTime,
            block.timestamp + ONE_DAY,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.expectRevert("cannot");
        alpha.withdraw(tradeId);
    }
    
    // ============================================================
    //                    MULTIPLE TRADES
    // ============================================================
    
    function test_MultipleConcurrentTrades() public {
        // Create 3 trades
        uint256[] memory tradeIds = new uint256[](3);
        
        for (uint i = 0; i < 3; i++) {
            tradeIds[i] = alpha.create(
                address(targetToken),
                1 ether,
                block.timestamp + ONE_HOUR * (i + 1),
                block.timestamp + ONE_DAY + ONE_HOUR * (i + 1),
                block.timestamp + ONE_HOUR * (i + 1) - 60,
                200
            );
            
            vm.prank(alice);
            alpha.join{value: 1 ether}(tradeIds[i]);
        }
        
        // Execute first trade
        vm.warp(block.timestamp + ONE_HOUR);
        alpha.executeBuy(tradeIds[0]);
        
        // Others still funding
        (,,,,,, AlphaTestable.Status status0,,) = alpha.getTradeInfo(tradeIds[0]);
        (,,,,,, AlphaTestable.Status status1,,) = alpha.getTradeInfo(tradeIds[1]);
        (,,,,,, AlphaTestable.Status status2,,) = alpha.getTradeInfo(tradeIds[2]);
        
        assertEq(uint256(status0), 1); // Bought
        assertEq(uint256(status1), 0); // Funding
        assertEq(uint256(status2), 0); // Funding
    }
    
    // ============================================================
    //                      FUZZ TESTS
    // ============================================================
    
    function testFuzz_ContributionsPreserved(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 0.01 ether, 25 ether);
        amount2 = bound(amount2, 0.01 ether, 25 ether);
        
        uint256 threshold = amount1 + amount2;
        uint256 buyTime = block.timestamp + ONE_HOUR;
        
        uint256 tradeId = alpha.create(
            address(targetToken),
            threshold,
            buyTime,
            block.timestamp + ONE_DAY,
            buyTime - 60,
            200
        );
        
        vm.prank(alice);
        alpha.join{value: amount1}(tradeId);
        
        vm.prank(bob);
        alpha.join{value: amount2}(tradeId);
        
        assertEq(alpha.getContribution(tradeId, alice), amount1);
        assertEq(alpha.getContribution(tradeId, bob), amount2);
    }
}
