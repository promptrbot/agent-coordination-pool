// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";

contract ACPTest is Test {
    ACP public acp;
    MockERC20 public token;
    
    address public controller = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    address public attacker = address(5);
    
    function setUp() public {
        acp = new ACP();
        token = new MockERC20("Test", "TEST", 18);
        
        // Fund test accounts
        vm.deal(controller, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(attacker, 100 ether);
    }
    
    // ============ Pool Creation ============
    
    function test_CreatePoolETH() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        (address poolToken, address poolController, uint256 total, uint256 count) = acp.getPoolInfo(poolId);
        
        assertEq(poolToken, address(0));
        assertEq(poolController, controller);
        assertEq(total, 0);
        assertEq(count, 0);
    }
    
    function test_CreatePoolERC20() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        (address poolToken,,,) = acp.getPoolInfo(poolId);
        assertEq(poolToken, address(token));
    }
    
    function test_PoolIdsIncrement() public {
        vm.startPrank(controller);
        uint256 id0 = acp.createPool(address(0));
        uint256 id1 = acp.createPool(address(0));
        uint256 id2 = acp.createPool(address(0));
        vm.stopPrank();
        
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(acp.poolCount(), 3);
    }
    
    // ============ ETH Contributions ============
    
    function test_ContributeETH() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        
        assertEq(acp.getContribution(poolId, alice), 1 ether);
    }
    
    function test_ContributeETH_MultipleContributors() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 2 ether}(poolId, bob);
        acp.contribute{value: 0.5 ether}(poolId, charlie);
        vm.stopPrank();
        
        (,, uint256 total, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(total, 3.5 ether);
        assertEq(count, 3);
    }
    
    function test_ContributeETH_Accumulates() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 2 ether}(poolId, alice);
        vm.stopPrank();
        
        assertEq(acp.getContribution(poolId, alice), 3 ether);
        
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, 1); // Still one contributor
    }
    
    function test_ContributeETH_RevertZeroValue() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        vm.expectRevert("no value");
        acp.contribute{value: 0}(poolId, alice);
    }
    
    function test_ContributeETH_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(attacker);
        vm.expectRevert(ACP.NotController.selector);
        acp.contribute{value: 1 ether}(poolId, alice);
    }
    
    // ============ ERC20 Contributions ============
    
    function test_ContributeToken() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 50 ether);
        vm.stopPrank();
        
        assertEq(acp.getContribution(poolId, alice), 50 ether);
        assertEq(token.balanceOf(address(acp)), 50 ether);
    }
    
    function test_ContributeToken_RevertWrongPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0)); // ETH pool
        
        vm.prank(controller);
        vm.expectRevert("not token pool");
        acp.contributeToken(poolId, alice, 100 ether);
    }
    
    function test_ContributeETH_RevertWrongPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token)); // Token pool
        
        vm.prank(controller);
        vm.expectRevert("not ETH pool");
        acp.contribute{value: 1 ether}(poolId, alice);
    }
    
    // ============ Execute ============
    
    function test_Execute() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.execute(poolId, bob, 3 ether, "");
        
        assertEq(bob.balance - bobBefore, 3 ether);
    }
    
    function test_Execute_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        vm.prank(attacker);
        vm.expectRevert(ACP.NotController.selector);
        acp.execute(poolId, attacker, 1 ether, "");
    }
    
    // ============ Deposit ============
    
    function test_Deposit() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.deposit{value: 10 ether}(poolId);
        
        assertEq(address(acp).balance, 10 ether);
    }
    
    function test_Deposit_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(attacker);
        vm.expectRevert(ACP.NotController.selector);
        acp.deposit{value: 1 ether}(poolId);
    }
    
    // ============ Distribute ETH ============
    
    function test_DistributeETH_ProRata() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Alice: 1 ETH (20%), Bob: 4 ETH (80%)
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 4 ether}(poolId, bob);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 1 ether);
        assertEq(bob.balance - bobBefore, 4 ether);
    }
    
    function test_DistributeETH_Profits() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Contribute 5 ETH total
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice); // 20%
        acp.contribute{value: 4 ether}(poolId, bob);   // 80%
        
        // Execute all, deposit double back (simulating profit)
        acp.execute(poolId, controller, 5 ether, "");
        acp.deposit{value: 10 ether}(poolId);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Alice: 20% of 10 = 2 ETH, Bob: 80% of 10 = 8 ETH
        assertEq(alice.balance - aliceBefore, 2 ether);
        assertEq(bob.balance - bobBefore, 8 ether);
    }
    
    function test_DistributeETH_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        
        vm.prank(attacker);
        vm.expectRevert(ACP.NotController.selector);
        acp.distribute(poolId, address(0));
    }
    
    // ============ Distribute ERC20 ============
    
    function test_DistributeERC20_ProRata() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice); // 20%
        acp.contribute{value: 4 ether}(poolId, bob);   // 80%
        vm.stopPrank();
        
        // Mint tokens to ACP (simulating received tokens)
        token.mint(address(acp), 1000 ether);
        
        vm.prank(controller);
        acp.distribute(poolId, address(token));
        
        // Alice: 20% = 200, Bob: 80% = 800
        assertEq(token.balanceOf(alice), 200 ether);
        assertEq(token.balanceOf(bob), 800 ether);
    }
    
    // ============ Edge Cases ============
    
    function test_SingleContributor() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        uint256 aliceBefore = alice.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 5 ether);
    }
    
    function test_TinyContributions() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1}(poolId, alice);
        acp.contribute{value: 1}(poolId, bob);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 1);
        assertEq(bob.balance - bobBefore, 1);
    }
    
    function test_ZeroBalanceDistribute() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.execute(poolId, controller, 1 ether, "");
        vm.stopPrank();
        
        // Should not revert, just send nothing
        vm.prank(controller);
        acp.distribute(poolId, address(0));
    }
    
    // ============ Pool Isolation ============
    
    function test_PoolsIsolated() public {
        vm.startPrank(controller);
        uint256 pool0 = acp.createPool(address(0));
        uint256 pool1 = acp.createPool(address(0));
        
        acp.contribute{value: 10 ether}(pool0, alice);
        acp.contribute{value: 5 ether}(pool1, bob);
        vm.stopPrank();
        
        (,, uint256 total0,) = acp.getPoolInfo(pool0);
        (,, uint256 total1,) = acp.getPoolInfo(pool1);
        
        assertEq(total0, 10 ether);
        assertEq(total1, 5 ether);
    }
    
    function test_CrossPoolExecuteFails() public {
        vm.startPrank(controller);
        uint256 pool0 = acp.createPool(address(0));
        uint256 pool1 = acp.createPool(address(0));
        
        acp.contribute{value: 10 ether}(pool0, alice);
        acp.contribute{value: 1 ether}(pool1, bob);
        
        // Try to execute more than pool 1 has
        vm.expectRevert();
        acp.execute(pool1, attacker, 5 ether, "");
        vm.stopPrank();
    }
    
    function test_DifferentControllers() public {
        vm.prank(alice);
        uint256 pool0 = acp.createPool(address(0)); // Alice controls
        
        vm.prank(bob);
        uint256 pool1 = acp.createPool(address(0)); // Bob controls
        
        // Alice can operate on pool 0
        vm.prank(alice);
        acp.contribute{value: 1 ether}(pool0, charlie);
        
        // Bob can operate on pool 1
        vm.prank(bob);
        acp.contribute{value: 1 ether}(pool1, charlie);
        
        // Alice cannot operate on pool 1
        vm.prank(alice);
        vm.expectRevert(ACP.NotController.selector);
        acp.contribute{value: 1 ether}(pool1, charlie);
        
        // Bob cannot operate on pool 0
        vm.prank(bob);
        vm.expectRevert(ACP.NotController.selector);
        acp.distribute(pool0, address(0));
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_ContributeAndDistribute(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 > 0 && amount2 > 0);
        vm.assume(uint256(amount1) + uint256(amount2) <= 100 ether);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: amount1}(poolId, alice);
        acp.contribute{value: amount2}(poolId, bob);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        uint256 aliceReceived = alice.balance - aliceBefore;
        uint256 bobReceived = bob.balance - bobBefore;
        
        // Total received should equal total contributed (minus dust)
        uint256 total = uint256(amount1) + uint256(amount2);
        uint256 received = aliceReceived + bobReceived;
        assertLe(total - received, 2); // At most 2 wei dust
    }
    
    function testFuzz_ProportionalDistribution(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 >= 1000 && amount2 >= 1000); // Avoid tiny amounts
        vm.assume(uint256(amount1) + uint256(amount2) <= 100 ether);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: amount1}(poolId, alice);
        acp.contribute{value: amount2}(poolId, bob);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        uint256 aliceReceived = alice.balance - aliceBefore;
        uint256 bobReceived = bob.balance - bobBefore;
        
        // Check proportionality: alice/bob ≈ amount1/amount2
        // Cross multiply: aliceReceived * amount2 ≈ bobReceived * amount1
        uint256 cross1 = aliceReceived * uint256(amount2);
        uint256 cross2 = bobReceived * uint256(amount1);
        
        // Allow 0.01% tolerance
        uint256 tolerance = (cross1 > cross2 ? cross1 : cross2) / 10000;
        uint256 diff = cross1 > cross2 ? cross1 - cross2 : cross2 - cross1;
        assertLe(diff, tolerance + 1);
    }
}
