// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockWETH.sol";
import "../../contracts/mocks/AlphaTestable.sol";
import "../../contracts/mocks/MockAerodrome.sol";

/// @title AlphaComprehensiveTest - Every possible edge case
contract AlphaComprehensiveTest is Test {
    ACP public acp;
    AlphaTestable public alpha;
    MockWETH public weth;
    MockERC20 public targetToken;
    MockAerodrome public router;
    
    address public alice = address(2);
    address public bob = address(3);
    
    uint256 constant ONE_HOUR = 3600;
    uint256 constant ONE_DAY = 86400;
    
    event TradeCreated(uint256 indexed tradeId, address tokenOut, uint256 threshold);
    event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
    event BuyExecuted(uint256 indexed tradeId, uint256 ethSpent, uint256 tokensReceived);
    event SellExecuted(uint256 indexed tradeId, uint256 tokensSold, uint256 ethReceived);
    
    function setUp() public {
        acp = new ACP();
        weth = new MockWETH();
        targetToken = new MockERC20("Target", "TGT", 18);
        router = new MockAerodrome();
        
        alpha = new AlphaTestable(address(acp), address(router), address(weth));
        
        // Fund router
        targetToken.mint(address(router), 10_000_000 ether);
        vm.deal(address(this), 10000 ether);
        weth.deposit{value: 10000 ether}();
        weth.transfer(address(router), 10000 ether);
        
        router.setExchangeRate(address(targetToken), 100000);
        router.setExchangeRate(address(weth), 1200);
        
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }
    
    // ============================================================
    //                    CREATE VALIDATION
    // ============================================================
    
    function test_Create_RevertZeroToken() public {
        vm.expectRevert("invalid token");
        alpha.create(
            address(0),
            1 ether,
            block.timestamp + ONE_HOUR,
            block.timestamp + ONE_DAY,
            block.timestamp + ONE_HOUR - 60,
            200
        );
    }
    
    function test_Create_RevertSellLessThanBuy() public {
        vm.expectRevert("sell<=buy");
        alpha.create(
            address(targetToken),
            1 ether,
            block.timestamp + ONE_DAY,      // buyTime
            block.timestamp + ONE_HOUR,     // sellTime < buyTime
            block.timestamp + ONE_HOUR - 60,
            200
        );
    }
    
    function test_Create_RevertSellEqualBuy() public {
        uint256 sameTime = block.timestamp + ONE_HOUR;
        vm.expectRevert("sell<=buy");
        alpha.create(
            address(targetToken),
            1 ether,
            sameTime,
            sameTime,
            sameTime - 60,
            200
        );
    }
    
    function test_Create_RevertDeadlineAfterBuy() public {
        vm.expectRevert("deadline>buy");
        alpha.create(
            address(targetToken),
            1 ether,
            block.timestamp + ONE_HOUR,     // buyTime
            block.timestamp + ONE_DAY,
            block.timestamp + ONE_HOUR + 1, // deadline > buyTime
            200
        );
    }
    
    function test_Create_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit TradeCreated(0, address(targetToken), 5 ether);
        
        alpha.create(
            address(targetToken),
            5 ether,
            block.timestamp + ONE_HOUR,
            block.timestamp + ONE_DAY,
            block.timestamp + ONE_HOUR - 60,
            200
        );
    }
    
    function test_Create_IncreasesCount() public {
        assertEq(alpha.count(), 0);
        
        alpha.create(address(targetToken), 1 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        assertEq(alpha.count(), 1);
        
        alpha.create(address(targetToken), 2 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        assertEq(alpha.count(), 2);
    }
    
    function test_Create_DeadlineEqualsBuyTime() public {
        // deadline == buyTime should work
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(
            address(targetToken),
            1 ether,
            buyTime,
            block.timestamp + ONE_DAY,
            buyTime, // deadline == buyTime
            200
        );
        
        assertEq(tradeId, 0);
    }
    
    // ============================================================
    //                    JOIN VALIDATION
    // ============================================================
    
    function test_Join_EmitsEvent() public {
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Joined(tradeId, alice, 2 ether);
        alpha.join{value: 2 ether}(tradeId);
    }
    
    function test_Join_AtExactDeadline() public {
        uint256 deadline = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, deadline + 60, block.timestamp + ONE_DAY, deadline, 200);
        
        // Warp to exact deadline
        vm.warp(deadline);
        
        // Should still work at exact deadline
        vm.prank(alice);
        alpha.join{value: 1 ether}(tradeId);
        
        assertEq(alpha.getContribution(tradeId, alice), 1 ether);
    }
    
    function test_Join_OneSecondAfterDeadline() public {
        uint256 deadline = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, deadline + 60, block.timestamp + ONE_DAY, deadline, 200);
        
        vm.warp(deadline + 1);
        
        vm.prank(alice);
        vm.expectRevert("closed");
        alpha.join{value: 1 ether}(tradeId);
    }
    
    function test_Join_SameUserMultipleTimes() public {
        uint256 tradeId = alpha.create(address(targetToken), 10 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        
        vm.startPrank(alice);
        alpha.join{value: 1 ether}(tradeId);
        alpha.join{value: 2 ether}(tradeId);
        alpha.join{value: 3 ether}(tradeId);
        vm.stopPrank();
        
        assertEq(alpha.getContribution(tradeId, alice), 6 ether);
    }
    
    function test_Join_ZeroValue() public {
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        
        vm.prank(alice);
        vm.expectRevert("no value");
        alpha.join{value: 0}(tradeId);
    }
    
    function test_Join_AfterBought() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 1 ether, buyTime, block.timestamp + ONE_DAY, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 1 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.prank(bob);
        vm.expectRevert("closed");
        alpha.join{value: 1 ether}(tradeId);
    }
    
    // ============================================================
    //                    EXECUTE BUY VALIDATION
    // ============================================================
    
    function test_ExecuteBuy_EmitsEvent() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, block.timestamp + ONE_DAY, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        
        vm.expectEmit(true, false, false, false);
        emit BuyExecuted(tradeId, 5 ether, 0); // Don't check exact amounts
        alpha.executeBuy(tradeId);
    }
    
    function test_ExecuteBuy_AtExactBuyTime() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, block.timestamp + ONE_DAY, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        (,,,,,, AlphaTestable.Status status,,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 1); // Bought
    }
    
    function test_ExecuteBuy_ThresholdExactlyMet() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, block.timestamp + ONE_DAY, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId); // Exactly threshold
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId); // Should work
        
        (,,,,,, AlphaTestable.Status status,,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 1);
    }
    
    function test_ExecuteBuy_ThresholdExceeded() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, block.timestamp + ONE_DAY, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 10 ether}(tradeId); // More than threshold
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId); // Should work with full amount
        
        (,,,,,, AlphaTestable.Status status, uint256 total,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 1);
        assertEq(total, 10 ether);
    }
    
    function test_ExecuteBuy_OneSecondBeforeBuyTime() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, block.timestamp + ONE_DAY, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime - 1);
        
        vm.expectRevert("too early");
        alpha.executeBuy(tradeId);
    }
    
    // ============================================================
    //                    EXECUTE SELL VALIDATION
    // ============================================================
    
    function test_ExecuteSell_EmitsEvent() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, sellTime, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.warp(sellTime);
        
        vm.expectEmit(true, false, false, false);
        emit SellExecuted(tradeId, 0, 0);
        alpha.executeSell(tradeId);
    }
    
    function test_ExecuteSell_AtExactSellTime() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, sellTime, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.warp(sellTime);
        alpha.executeSell(tradeId);
        
        (,,,,,, AlphaTestable.Status status,,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 2); // Sold
    }
    
    function test_ExecuteSell_OneSecondBeforeSellTime() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, sellTime, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.warp(sellTime - 1);
        
        vm.expectRevert("too early");
        alpha.executeSell(tradeId);
    }
    
    // ============================================================
    //                    CLAIM & WITHDRAW
    // ============================================================
    
    function test_Claim_AlreadyClaimed() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, sellTime, buyTime - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 5 ether}(tradeId);
        
        vm.warp(buyTime);
        alpha.executeBuy(tradeId);
        
        vm.warp(sellTime);
        alpha.executeSell(tradeId);
        
        // First claim
        alpha.claim(tradeId);
        
        // Second claim - does nothing (pool already empty)
        uint256 aliceBefore = alice.balance;
        alpha.claim(tradeId);
        assertEq(alice.balance, aliceBefore);
    }
    
    function test_Withdraw_SetsStatusExpired() public {
        uint256 deadline = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 100 ether, deadline + 60, block.timestamp + ONE_DAY, deadline, 200);
        
        vm.prank(alice);
        alpha.join{value: 1 ether}(tradeId);
        
        vm.warp(deadline + 1);
        alpha.withdraw(tradeId);
        
        (,,,,,, AlphaTestable.Status status,,) = alpha.getTradeInfo(tradeId);
        assertEq(uint256(status), 3); // Expired
    }
    
    function test_Withdraw_BeforeDeadline() public {
        uint256 deadline = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 100 ether, deadline + 60, block.timestamp + ONE_DAY, deadline, 200);
        
        vm.prank(alice);
        alpha.join{value: 1 ether}(tradeId);
        
        vm.expectRevert("cannot");
        alpha.withdraw(tradeId);
    }
    
    function test_Withdraw_AfterExpired() public {
        uint256 deadline = block.timestamp + ONE_HOUR;
        uint256 tradeId = alpha.create(address(targetToken), 100 ether, deadline + 60, block.timestamp + ONE_DAY, deadline, 200);
        
        vm.prank(alice);
        alpha.join{value: 1 ether}(tradeId);
        
        vm.warp(deadline + 1);
        alpha.withdraw(tradeId);
        
        // Second withdraw - already expired
        vm.expectRevert("cannot");
        alpha.withdraw(tradeId);
    }
    
    // ============================================================
    //                    VIEW FUNCTIONS
    // ============================================================
    
    function test_GetTradeInfo_AllFields() public {
        uint256 buyTime = block.timestamp + ONE_HOUR;
        uint256 sellTime = block.timestamp + ONE_DAY;
        uint256 deadline = buyTime - 60;
        
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, buyTime, sellTime, deadline, 200);
        
        vm.prank(alice);
        alpha.join{value: 3 ether}(tradeId);
        
        (
            address tokenOut,
            uint256 threshold,
            uint256 bt,
            uint256 st,
            uint256 dl,
            uint256 tokensHeld,
            AlphaTestable.Status status,
            uint256 total,
            uint256 count
        ) = alpha.getTradeInfo(tradeId);
        
        assertEq(tokenOut, address(targetToken));
        assertEq(threshold, 5 ether);
        assertEq(bt, buyTime);
        assertEq(st, sellTime);
        assertEq(dl, deadline);
        assertEq(tokensHeld, 0);
        assertEq(uint256(status), 0); // Funding
        assertEq(total, 3 ether);
        assertEq(count, 1);
    }
    
    function test_GetContribution_NonContributor() public {
        uint256 tradeId = alpha.create(address(targetToken), 5 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        
        vm.prank(alice);
        alpha.join{value: 1 ether}(tradeId);
        
        assertEq(alpha.getContribution(tradeId, bob), 0);
    }
    
    function test_TradesArray_DirectAccess() public {
        alpha.create(address(targetToken), 5 ether, block.timestamp + ONE_HOUR, block.timestamp + ONE_DAY, block.timestamp + ONE_HOUR - 60, 200);
        
        (
            uint256 poolId,
            address tokenOut,
            uint256 threshold,
            uint256 buyTime,
            uint256 sellTime,
            uint256 deadline,
            int24 tickSpacing,
            uint256 tokensHeld,
            AlphaTestable.Status status
        ) = alpha.trades(0);
        
        assertEq(poolId, 0);
        assertEq(tokenOut, address(targetToken));
        assertEq(threshold, 5 ether);
        assertGt(buyTime, block.timestamp);
        assertGt(sellTime, buyTime);
        assertLe(deadline, buyTime);
        assertEq(tickSpacing, 200);
        assertEq(tokensHeld, 0);
        assertEq(uint256(status), 0);
    }
    
    // ============================================================
    //                    INVALID TRADE IDS
    // ============================================================
    
    function test_Join_InvalidTradeId() public {
        vm.prank(alice);
        vm.expectRevert(); // Array out of bounds
        alpha.join{value: 1 ether}(999);
    }
    
    function test_ExecuteBuy_InvalidTradeId() public {
        vm.expectRevert();
        alpha.executeBuy(999);
    }
    
    function test_GetTradeInfo_InvalidTradeId() public {
        vm.expectRevert();
        alpha.getTradeInfo(999);
    }
    
    // ============================================================
    //                    RECEIVE FUNCTION
    // ============================================================
    
    function test_Receive() public {
        (bool ok,) = address(alpha).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(alpha).balance, 1 ether);
    }
}
