// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";

/// @title ACPComprehensiveTest - Every possible edge case
contract ACPComprehensiveTest is Test {
    ACP public acp;
    MockERC20 public token;
    MockERC20 public token2;
    
    address public controller = address(1);
    address public alice = address(2);
    address public bob = address(3);
    
    function setUp() public {
        acp = new ACP();
        token = new MockERC20("Token1", "TK1", 18);
        token2 = new MockERC20("Token2", "TK2", 18);
        
        vm.deal(controller, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }
    
    // ============================================================
    //                    EXECUTE EDGE CASES
    // ============================================================
    
    function test_Execute_ZeroValue() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        
        // Execute with zero value should work
        vm.prank(controller);
        acp.execute(poolId, bob, 0, "");
        
        // Balance unchanged
        assertEq(acp.getPoolBalance(poolId), 1 ether);
    }
    
    function test_Execute_ToEOA() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        // Use an address that's not a precompile
        address realEOA = address(0x1234567890123456789012345678901234567890);
        uint256 eoaBefore = realEOA.balance;
        
        // Execute to EOA (not contract)
        vm.prank(controller);
        bytes memory result = acp.execute(poolId, realEOA, 1 ether, "");
        
        assertEq(realEOA.balance - eoaBefore, 1 ether);
        assertEq(result.length, 0); // EOA returns no data
    }
    
    function test_Execute_WithDataNoValue() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        DataRecorder recorder = new DataRecorder();
        
        // Execute with data but zero ETH
        vm.prank(controller);
        acp.execute(poolId, address(recorder), 0, abi.encodeWithSignature("record(uint256)", 42));
        
        assertEq(recorder.lastValue(), 42);
        assertEq(address(recorder).balance, 0);
    }
    
    function test_Execute_ERC20_ZeroValue() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 100 ether);
        vm.stopPrank();
        
        // Execute with zero value on ERC20 pool - no allowance set
        vm.prank(controller);
        acp.execute(poolId, bob, 0, "");
        
        // Check allowance was NOT set (value was 0)
        assertEq(token.allowance(address(acp), bob), 0);
    }
    
    // ============================================================
    //                    CONTRIBUTION EDGE CASES
    // ============================================================
    
    function test_Contribute_SameAddressMultipleTimes() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 2 ether}(poolId, alice);
        acp.contribute{value: 3 ether}(poolId, alice);
        acp.contribute{value: 4 ether}(poolId, alice);
        vm.stopPrank();
        
        assertEq(acp.getContribution(poolId, alice), 10 ether);
        
        // Only counted as one contributor
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, 1);
        
        address[] memory contributors = acp.getContributors(poolId);
        assertEq(contributors.length, 1);
        assertEq(contributors[0], alice);
    }
    
    function test_GetContribution_NonContributor() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        
        // Bob never contributed
        assertEq(acp.getContribution(poolId, bob), 0);
    }
    
    function test_ContributeToken_InsufficientBalance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        // Controller has 0 tokens but tries to contribute
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        
        vm.expectRevert();
        acp.contributeToken(poolId, alice, 100 ether);
        vm.stopPrank();
    }
    
    function test_ContributeToken_InsufficientAllowance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 10 ether); // Only approve 10
        
        vm.expectRevert();
        acp.contributeToken(poolId, alice, 50 ether); // Try to contribute 50
        vm.stopPrank();
    }
    
    function test_DepositToken_InsufficientBalance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        
        vm.expectRevert();
        acp.depositToken(poolId, address(token), 100 ether);
        vm.stopPrank();
    }
    
    // ============================================================
    //                    DISTRIBUTION EDGE CASES
    // ============================================================
    
    function test_Distribute_EmptyPool_NoContributors() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Pool has no contributors, no balance
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Should complete without error
    }
    
    function test_Distribute_ZeroTotalContributed() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Deposit without contributing
        vm.prank(controller);
        acp.deposit{value: 10 ether}(poolId);
        
        // No contributors, so distribute does nothing
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Balance is zeroed but nobody received (divide by zero handled)
        assertEq(acp.getPoolBalance(poolId), 0);
    }
    
    function test_Distribute_SamePoolTwice() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        
        // First distribute
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 10 ether);
        
        // Second distribute - nothing left
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // No change
        assertEq(alice.balance - aliceBefore, 10 ether);
    }
    
    function test_Distribute_ERC20_MultiplePoolsSameToken() public {
        // Two pools using same token for distribution
        vm.startPrank(controller);
        uint256 pool1 = acp.createPool(address(0));
        uint256 pool2 = acp.createPool(address(0));
        
        acp.contribute{value: 10 ether}(pool1, alice);
        acp.contribute{value: 10 ether}(pool2, bob);
        vm.stopPrank();
        
        // Mint tokens to ACP
        token.mint(address(acp), 100 ether);
        
        // Distribute token from pool1 - takes entire balance!
        vm.prank(controller);
        acp.distribute(pool1, address(token));
        
        assertEq(token.balanceOf(alice), 100 ether);
        
        // Pool2 distribute token - nothing left
        vm.prank(controller);
        acp.distribute(pool2, address(token));
        
        assertEq(token.balanceOf(bob), 0);
    }
    
    // ============================================================
    //                    POOL INFO EDGE CASES
    // ============================================================
    
    function test_PoolCount() public {
        assertEq(acp.poolCount(), 0);
        
        vm.startPrank(controller);
        acp.createPool(address(0));
        assertEq(acp.poolCount(), 1);
        
        acp.createPool(address(token));
        assertEq(acp.poolCount(), 2);
        
        acp.createPool(address(0));
        assertEq(acp.poolCount(), 3);
        vm.stopPrank();
    }
    
    function test_GetPoolInfo_ValidPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        (address poolToken, address poolController, uint256 total, uint256 count) = acp.getPoolInfo(poolId);
        
        assertEq(poolToken, address(token));
        assertEq(poolController, controller);
        assertEq(total, 0);
        assertEq(count, 0);
    }
    
    function test_GetPoolInfo_AfterContributions() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        acp.contribute{value: 3 ether}(poolId, bob);
        vm.stopPrank();
        
        (address poolToken, address poolController, uint256 total, uint256 count) = acp.getPoolInfo(poolId);
        
        assertEq(poolToken, address(0));
        assertEq(poolController, controller);
        assertEq(total, 8 ether);
        assertEq(count, 2);
    }
    
    function test_GetContributors_Empty() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        address[] memory contributors = acp.getContributors(poolId);
        assertEq(contributors.length, 0);
    }
    
    function test_GetContributors_Order() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 1 ether}(poolId, bob);
        acp.contribute{value: 1 ether}(poolId, controller);
        vm.stopPrank();
        
        address[] memory contributors = acp.getContributors(poolId);
        assertEq(contributors.length, 3);
        assertEq(contributors[0], alice);
        assertEq(contributors[1], bob);
        assertEq(contributors[2], controller);
    }
    
    // ============================================================
    //                    TOKEN POOL EDGE CASES
    // ============================================================
    
    function test_TokenPool_BalanceTracking() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 30 ether);
        acp.contributeToken(poolId, bob, 20 ether);
        vm.stopPrank();
        
        assertEq(acp.getPoolBalance(poolId), 50 ether);
        assertEq(token.balanceOf(address(acp)), 50 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 50 ether);
        acp.depositToken(poolId, address(token), 25 ether);
        vm.stopPrank();
        
        assertEq(acp.getPoolTokenBalance(poolId, address(token)), 25 ether);
    }
    
    function test_TokenPool_Execute_UpdatesAllowance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 100 ether);
        vm.stopPrank();
        
        // Check initial allowance
        assertEq(token.allowance(address(acp), bob), 0);
        
        // Execute sets allowance
        vm.prank(controller);
        acp.execute(poolId, bob, 50 ether, "");
        
        // Allowance should be set (safeIncreaseAllowance)
        assertGe(token.allowance(address(acp), bob), 50 ether);
    }
    
    // ============================================================
    //                    BOUNDARY CONDITIONS
    // ============================================================
    
    function test_Contribute_MaxUint() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Give controller max ETH
        vm.deal(controller, type(uint256).max);
        
        // Contribute a very large amount
        vm.prank(controller);
        acp.contribute{value: 1e30}(poolId, alice);
        
        assertEq(acp.getContribution(poolId, alice), 1e30);
    }
    
    function test_Contribute_OneWei() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1}(poolId, alice);
        
        assertEq(acp.getContribution(poolId, alice), 1);
    }
    
    function test_Execute_EntireBalance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        vm.prank(controller);
        acp.execute(poolId, bob, 10 ether, "");
        
        assertEq(acp.getPoolBalance(poolId), 0);
    }
    
    function test_Execute_MoreThanBalance_Reverts() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        vm.prank(controller);
        vm.expectRevert(ACP.InsufficientBalance.selector);
        acp.execute(poolId, bob, 10 ether + 1, "");
    }
    
    // ============================================================
    //                    RECEIVE FUNCTION
    // ============================================================
    
    function test_Receive_DirectTransfer() public {
        uint256 before = address(acp).balance;
        
        (bool ok,) = address(acp).call{value: 5 ether}("");
        assertTrue(ok);
        
        assertEq(address(acp).balance - before, 5 ether);
    }
    
    function test_Receive_FromContract() public {
        ETHSender sender = new ETHSender{value: 10 ether}();
        
        sender.sendTo(payable(address(acp)), 5 ether);
        
        assertEq(address(acp).balance, 5 ether);
    }
    
    // ============================================================
    //                    GAS OPTIMIZATION
    // ============================================================
    
    function test_Gas_CreatePool() public {
        uint256 gasBefore = gasleft();
        vm.prank(controller);
        acp.createPool(address(0));
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 100_000);
    }
    
    function test_Gas_Contribute() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        uint256 gasBefore = gasleft();
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 150_000);
    }
    
    function test_Gas_Execute() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        uint256 gasBefore = gasleft();
        vm.prank(controller);
        acp.execute(poolId, bob, 1 ether, "");
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 50_000);
    }
}

contract DataRecorder {
    uint256 public lastValue;
    
    function record(uint256 value) external {
        lastValue = value;
    }
}

contract ETHSender {
    constructor() payable {}
    
    function sendTo(address payable to, uint256 amount) external {
        to.transfer(amount);
    }
}
