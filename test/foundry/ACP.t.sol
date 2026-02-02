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
    
    event PoolCreated(uint256 indexed poolId, address indexed controller, address token);
    event Contributed(uint256 indexed poolId, address indexed contributor, uint256 amount);
    event Executed(uint256 indexed poolId, address indexed target, uint256 value, bool success);
    event Distributed(uint256 indexed poolId, address token, uint256 totalAmount);
    
    function setUp() public {
        acp = new ACP();
        token = new MockERC20("Test", "TEST", 18);
        
        vm.deal(controller, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(charlie, 1000 ether);
        vm.deal(attacker, 1000 ether);
    }
    
    // ============================================================
    //                       POOL CREATION
    // ============================================================
    
    function test_CreatePoolETH() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        (address poolToken, address poolController, uint256 total, uint256 count) = acp.getPoolInfo(poolId);
        
        assertEq(poolId, 0);
        assertEq(poolToken, address(0));
        assertEq(poolController, controller);
        assertEq(total, 0);
        assertEq(count, 0);
    }
    
    function test_CreatePoolERC20() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        (address poolToken, address poolController,,) = acp.getPoolInfo(poolId);
        assertEq(poolToken, address(token));
        assertEq(poolController, controller);
    }
    
    function test_CreatePool_EmitsEvent() public {
        vm.prank(controller);
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(0, controller, address(0));
        acp.createPool(address(0));
    }
    
    function test_PoolIdsIncrement() public {
        vm.startPrank(controller);
        assertEq(acp.createPool(address(0)), 0);
        assertEq(acp.createPool(address(0)), 1);
        assertEq(acp.createPool(address(0)), 2);
        vm.stopPrank();
        
        assertEq(acp.poolCount(), 3);
    }
    
    function test_AnyoneCanCreatePool() public {
        vm.prank(alice);
        uint256 id1 = acp.createPool(address(0));
        
        vm.prank(bob);
        uint256 id2 = acp.createPool(address(0));
        
        (,address ctrl1,,) = acp.getPoolInfo(id1);
        (,address ctrl2,,) = acp.getPoolInfo(id2);
        
        assertEq(ctrl1, alice);
        assertEq(ctrl2, bob);
    }
    
    // ============================================================
    //                    ETH CONTRIBUTIONS
    // ============================================================
    
    function test_ContributeETH() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        
        assertEq(acp.getContribution(poolId, alice), 1 ether);
        assertEq(address(acp).balance, 1 ether);
    }
    
    function test_ContributeETH_EmitsEvent() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        vm.expectEmit(true, true, false, true);
        emit Contributed(poolId, alice, 1 ether);
        acp.contribute{value: 1 ether}(poolId, alice);
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
        
        address[] memory contributors = acp.getContributors(poolId);
        assertEq(contributors.length, 3);
        assertEq(contributors[0], alice);
        assertEq(contributors[1], bob);
        assertEq(contributors[2], charlie);
    }
    
    function test_ContributeETH_Accumulates() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 2 ether}(poolId, alice);
        acp.contribute{value: 0.5 ether}(poolId, alice);
        vm.stopPrank();
        
        assertEq(acp.getContribution(poolId, alice), 3.5 ether);
        
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
    
    function test_ContributeETH_RevertTokenPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        vm.prank(controller);
        vm.expectRevert("not ETH pool");
        acp.contribute{value: 1 ether}(poolId, alice);
    }
    
    // ============================================================
    //                   ERC20 CONTRIBUTIONS
    // ============================================================
    
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
    
    function test_ContributeToken_EmitsEvent() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        
        vm.expectEmit(true, true, false, true);
        emit Contributed(poolId, alice, 50 ether);
        acp.contributeToken(poolId, alice, 50 ether);
        vm.stopPrank();
    }
    
    function test_ContributeToken_RevertETHPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        vm.expectRevert("not token pool");
        acp.contributeToken(poolId, alice, 100 ether);
    }
    
    function test_ContributeToken_RevertZeroAmount() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        vm.prank(controller);
        vm.expectRevert("no value");
        acp.contributeToken(poolId, alice, 0);
    }
    
    function test_ContributeToken_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(attacker, 100 ether);
        vm.startPrank(attacker);
        token.approve(address(acp), 100 ether);
        
        vm.expectRevert(ACP.NotController.selector);
        acp.contributeToken(poolId, alice, 50 ether);
        vm.stopPrank();
    }
    
    // ============================================================
    //                         EXECUTE
    // ============================================================
    
    function test_Execute_TransferETH() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.execute(poolId, bob, 3 ether, "");
        
        assertEq(bob.balance - bobBefore, 3 ether);
        assertEq(acp.getPoolBalance(poolId), 7 ether);
    }
    
    function test_Execute_EmitsEvent() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        vm.prank(controller);
        vm.expectEmit(true, true, false, true);
        emit Executed(poolId, bob, 3 ether, true);
        acp.execute(poolId, bob, 3 ether, "");
    }
    
    function test_Execute_CallContract() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        // Deploy a simple receiver contract
        SimpleReceiver receiver = new SimpleReceiver();
        
        vm.prank(controller);
        bytes memory result = acp.execute(poolId, address(receiver), 1 ether, abi.encodeWithSignature("receiveAndReturn()"));
        
        assertEq(abi.decode(result, (uint256)), 42);
        assertEq(address(receiver).balance, 1 ether);
    }
    
    function test_Execute_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        vm.prank(attacker);
        vm.expectRevert(ACP.NotController.selector);
        acp.execute(poolId, attacker, 1 ether, "");
    }
    
    function test_Execute_RevertInsufficientBalance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        
        vm.prank(controller);
        vm.expectRevert("Insufficient balance");
        acp.execute(poolId, bob, 2 ether, "");
    }
    
    function test_Execute_BubblesUpRevert() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        RevertingReceiver reverter = new RevertingReceiver();
        
        vm.prank(controller);
        vm.expectRevert("I always revert");
        acp.execute(poolId, address(reverter), 1 ether, "");
    }
    
    // ============================================================
    //                         DEPOSIT
    // ============================================================
    
    function test_Deposit() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.deposit{value: 10 ether}(poolId);
        
        assertEq(acp.getPoolBalance(poolId), 10 ether);
        assertEq(address(acp).balance, 10 ether);
    }
    
    function test_Deposit_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(attacker);
        vm.expectRevert(ACP.NotController.selector);
        acp.deposit{value: 1 ether}(poolId);
    }
    
    function test_Deposit_RevertTokenPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        vm.prank(controller);
        vm.expectRevert("ETH pools only");
        acp.deposit{value: 1 ether}(poolId);
    }
    
    function test_DepositToken() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.depositToken(poolId, 50 ether);
        vm.stopPrank();
        
        assertEq(acp.getPoolBalance(poolId), 50 ether);
        assertEq(token.balanceOf(address(acp)), 50 ether);
    }
    
    function test_DepositToken_RevertETHPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        vm.expectRevert("Token pools only");
        acp.depositToken(poolId, 50 ether);
    }
    
    function test_DepositToken_RevertNotController() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(attacker, 100 ether);
        vm.startPrank(attacker);
        token.approve(address(acp), 100 ether);
        
        vm.expectRevert(ACP.NotController.selector);
        acp.depositToken(poolId, 50 ether);
        vm.stopPrank();
    }
    
    // ============================================================
    //                     DISTRIBUTE ETH
    // ============================================================
    
    function test_DistributeETH_ProRata() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);   // 20%
        acp.contribute{value: 4 ether}(poolId, bob);     // 80%
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 1 ether);
        assertEq(bob.balance - bobBefore, 4 ether);
    }
    
    function test_DistributeETH_EmitsEvent() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        vm.prank(controller);
        vm.expectEmit(true, false, false, true);
        emit Distributed(poolId, address(0), 5 ether);
        acp.distribute(poolId, address(0));
    }
    
    function test_DistributeETH_WithProfits() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);   // 20%
        acp.contribute{value: 4 ether}(poolId, bob);     // 80%
        
        // Simulate profit: execute out, deposit back double
        acp.execute(poolId, controller, 5 ether, "");
        acp.deposit{value: 10 ether}(poolId);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 2 ether);  // 20% of 10
        assertEq(bob.balance - bobBefore, 8 ether);      // 80% of 10
    }
    
    function test_DistributeETH_WithLoss() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 2 ether}(poolId, alice);   // 40%
        acp.contribute{value: 3 ether}(poolId, bob);     // 60%
        
        // Simulate loss: execute out, deposit back half
        acp.execute(poolId, controller, 5 ether, "");
        acp.deposit{value: 2.5 ether}(poolId);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, 1 ether);    // 40% of 2.5
        assertEq(bob.balance - bobBefore, 1.5 ether);      // 60% of 2.5
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
    
    function test_DistributeETH_TransferFailed() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Use a contract that rejects ETH as contributor
        RejectingReceiver rejecter = new RejectingReceiver();
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, address(rejecter));
        
        vm.prank(controller);
        vm.expectRevert(ACP.TransferFailed.selector);
        acp.distribute(poolId, address(0));
    }
    
    // ============================================================
    //                    DISTRIBUTE ERC20
    // ============================================================
    
    function test_DistributeERC20_ProRata() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);   // 20%
        acp.contribute{value: 4 ether}(poolId, bob);     // 80%
        vm.stopPrank();
        
        // Mint tokens to ACP (simulating token acquisition)
        token.mint(address(acp), 1000 ether);
        
        vm.prank(controller);
        acp.distribute(poolId, address(token));
        
        assertEq(token.balanceOf(alice), 200 ether);   // 20%
        assertEq(token.balanceOf(bob), 800 ether);     // 80%
    }
    
    function test_DistributeERC20_EmitsEvent() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        token.mint(address(acp), 100 ether);
        
        vm.prank(controller);
        vm.expectEmit(true, false, false, true);
        emit Distributed(poolId, address(token), 100 ether);
        acp.distribute(poolId, address(token));
    }
    
    // ============================================================
    //                      EDGE CASES
    // ============================================================
    
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
        
        uint256 aliceBefore = alice.balance;
        
        // Should not revert, just send nothing
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance, aliceBefore);
    }
    
    function test_DustRemains() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // 3 contributors, 10 wei - can't divide evenly
        vm.startPrank(controller);
        acp.contribute{value: 3}(poolId, alice);
        acp.contribute{value: 3}(poolId, bob);
        acp.contribute{value: 4}(poolId, charlie);
        vm.stopPrank();
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Dust stays in contract
        assertLe(address(acp).balance, 2);
    }
    
    function test_ManyContributors() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // 50 contributors
        for (uint i = 10; i < 60; i++) {
            address contributor = address(uint160(i));
            vm.deal(contributor, 1 ether);
            vm.prank(controller);
            acp.contribute{value: 0.1 ether}(poolId, contributor);
        }
        
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, 50);
        
        // Should distribute without running out of gas
        vm.prank(controller);
        acp.distribute(poolId, address(0));
    }
    
    // ============================================================
    //                    POOL ISOLATION
    // ============================================================
    
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
        assertEq(acp.getPoolBalance(pool0), 10 ether);
        assertEq(acp.getPoolBalance(pool1), 5 ether);
    }
    
    function test_CrossPoolExecuteFails() public {
        vm.startPrank(controller);
        uint256 pool0 = acp.createPool(address(0));
        uint256 pool1 = acp.createPool(address(0));
        
        acp.contribute{value: 10 ether}(pool0, alice);
        acp.contribute{value: 1 ether}(pool1, bob);
        
        // Try to execute more than pool 1 has
        vm.expectRevert("Insufficient balance");
        acp.execute(pool1, attacker, 5 ether, "");
        vm.stopPrank();
    }
    
    function test_DifferentControllers() public {
        vm.prank(alice);
        uint256 pool0 = acp.createPool(address(0));
        
        vm.prank(bob);
        uint256 pool1 = acp.createPool(address(0));
        
        // Alice operates pool 0
        vm.prank(alice);
        acp.contribute{value: 1 ether}(pool0, charlie);
        
        // Bob operates pool 1
        vm.prank(bob);
        acp.contribute{value: 1 ether}(pool1, charlie);
        
        // Cross-controller fails
        vm.prank(alice);
        vm.expectRevert(ACP.NotController.selector);
        acp.contribute{value: 1 ether}(pool1, charlie);
        
        vm.prank(bob);
        vm.expectRevert(ACP.NotController.selector);
        acp.distribute(pool0, address(0));
    }
    
    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================
    
    function test_GetContributors() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);
        acp.contribute{value: 1 ether}(poolId, bob);
        acp.contribute{value: 1 ether}(poolId, charlie);
        vm.stopPrank();
        
        address[] memory contributors = acp.getContributors(poolId);
        assertEq(contributors.length, 3);
        assertEq(contributors[0], alice);
        assertEq(contributors[1], bob);
        assertEq(contributors[2], charlie);
    }
    
    function test_GetPoolBalance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        assertEq(acp.getPoolBalance(poolId), 0);
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        assertEq(acp.getPoolBalance(poolId), 5 ether);
        
        vm.prank(controller);
        acp.execute(poolId, bob, 2 ether, "");
        
        assertEq(acp.getPoolBalance(poolId), 3 ether);
        
        vm.prank(controller);
        acp.deposit{value: 1 ether}(poolId);
        
        assertEq(acp.getPoolBalance(poolId), 4 ether);
    }
    
    // ============================================================
    //                    EXECUTE ERC20
    // ============================================================
    
    function test_Execute_ERC20_Allowance() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 100 ether);
        vm.stopPrank();
        
        // Deploy a token receiver
        TokenReceiver receiver = new TokenReceiver();
        
        // Execute should set allowance for target
        vm.prank(controller);
        acp.execute(
            poolId, 
            address(receiver), 
            50 ether, 
            abi.encodeWithSignature("onTokenReceived(address,uint256)", address(token), 50 ether)
        );
        
        // Token receiver got the tokens and sent them back
        assertEq(token.balanceOf(address(receiver)), 0);
    }
    
    // ============================================================
    //                    REENTRANCY TESTS
    // ============================================================
    
    function test_Reentrancy_Distribute() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        ReentrantAttacker reentrancyAttacker = new ReentrantAttacker(payable(address(acp)));
        reentrancyAttacker.setPoolId(poolId);
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, address(reentrancyAttacker));
        acp.contribute{value: 1 ether}(poolId, alice);
        vm.stopPrank();
        
        // Distribute - reentrancyAttacker will try to re-enter
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Attacker should only get their fair share (1 ether), not more
        assertEq(address(reentrancyAttacker).balance, 1 ether);
        assertEq(alice.balance, 1001 ether); // 1000 initial + 1 distributed
    }
    
    // ============================================================
    //                    INVALID POOL IDS
    // ============================================================
    
    function test_InvalidPoolId_Contribute() public {
        vm.prank(controller);
        vm.expectRevert(ACP.NotController.selector);
        acp.contribute{value: 1 ether}(999, alice);
    }
    
    function test_InvalidPoolId_Execute() public {
        vm.prank(controller);
        vm.expectRevert(ACP.NotController.selector);
        acp.execute(999, bob, 1 ether, "");
    }
    
    function test_InvalidPoolId_Distribute() public {
        vm.prank(controller);
        vm.expectRevert(ACP.NotController.selector);
        acp.distribute(999, address(0));
    }
    
    function test_InvalidPoolId_GetInfo() public view {
        // Should return zeros, not revert
        (address poolToken, address poolController, uint256 total, uint256 count) = acp.getPoolInfo(999);
        assertEq(poolToken, address(0));
        assertEq(poolController, address(0));
        assertEq(total, 0);
        assertEq(count, 0);
    }
    
    // ============================================================
    //                    ZERO ADDRESS
    // ============================================================
    
    function test_ZeroAddressContributor() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Contributing to zero address should work (it's just an address)
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, address(0));
        
        assertEq(acp.getContribution(poolId, address(0)), 1 ether);
    }
    
    function test_ZeroAddressContributor_DistributeFails() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 1 ether}(poolId, address(0));
        
        // Distribute to zero address will fail (can't send ETH to 0x0)
        vm.prank(controller);
        vm.expectRevert(ACP.TransferFailed.selector);
        acp.distribute(poolId, address(0));
    }
    
    // ============================================================
    //                    RECEIVE FALLBACK
    // ============================================================
    
    function test_ReceiveFallback() public {
        // Direct ETH send to ACP should work
        (bool ok,) = address(acp).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(acp).balance, 1 ether);
    }
    
    function test_ReceiveFallback_DoesNotAffectPools() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 5 ether}(poolId, alice);
        
        // Direct ETH send
        (bool ok,) = address(acp).call{value: 1 ether}("");
        assertTrue(ok);
        
        // Pool balance unchanged
        assertEq(acp.getPoolBalance(poolId), 5 ether);
        
        // Contract has more but pool tracks separately
        assertEq(address(acp).balance, 6 ether);
    }
    
    // ============================================================
    //                    ERC20 DISTRIBUTION
    // ============================================================
    
    function test_DistributeERC20_FromTokenPool() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(token));
        
        token.mint(controller, 100 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 40 ether);  // 40%
        acp.contributeToken(poolId, bob, 60 ether);    // 60%
        vm.stopPrank();
        
        // Distribute the same token
        vm.prank(controller);
        acp.distribute(poolId, address(token));
        
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(bob), 60 ether);
    }
    
    function test_DistributeERC20_DifferentToken() public {
        MockERC20 rewardToken = new MockERC20("Reward", "RWD", 18);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 1 ether}(poolId, alice);  // 50%
        acp.contribute{value: 1 ether}(poolId, bob);    // 50%
        vm.stopPrank();
        
        // Mint reward tokens to ACP
        rewardToken.mint(address(acp), 1000 ether);
        
        // Distribute reward token
        vm.prank(controller);
        acp.distribute(poolId, address(rewardToken));
        
        assertEq(rewardToken.balanceOf(alice), 500 ether);
        assertEq(rewardToken.balanceOf(bob), 500 ether);
    }
    
    // ============================================================
    //                    GAS LIMITS (100+ CONTRIBUTORS)
    // ============================================================
    
    function test_ManyContributors_100() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // 100 contributors
        for (uint i = 100; i < 200; i++) {
            address contributor = address(uint160(i));
            vm.prank(controller);
            acp.contribute{value: 0.1 ether}(poolId, contributor);
        }
        
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, 100);
        
        uint256 gasBefore = gasleft();
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should complete in reasonable gas (< 5M)
        assertLt(gasUsed, 5_000_000);
    }
    
    function test_ManyContributors_200() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // 200 contributors
        for (uint i = 100; i < 300; i++) {
            address contributor = address(uint160(i));
            vm.prank(controller);
            acp.contribute{value: 0.05 ether}(poolId, contributor);
        }
        
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, 200);
        
        uint256 gasBefore = gasleft();
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should complete (< 10M)
        assertLt(gasUsed, 10_000_000);
    }
    
    // ============================================================
    //                    FEE-ON-TRANSFER TOKENS
    // ============================================================
    
    function test_FeeOnTransferToken() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.mint(controller, 100 ether);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(feeToken));
        
        vm.startPrank(controller);
        feeToken.approve(address(acp), 100 ether);
        
        // Contribute 100, but only 99 arrives due to 1% fee
        acp.contributeToken(poolId, alice, 100 ether);
        vm.stopPrank();
        
        // ACP received less than contributed amount
        assertEq(feeToken.balanceOf(address(acp)), 99 ether);
        
        // But contribution is recorded as 100
        assertEq(acp.getContribution(poolId, alice), 100 ether);
        
        // This is a known limitation - fee tokens cause accounting mismatch
    }
    
    // ============================================================
    //                    COMPLEX EXECUTE RETURNS
    // ============================================================
    
    function test_Execute_ComplexReturn() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        ComplexReturnContract complexContract = new ComplexReturnContract();
        
        vm.prank(controller);
        bytes memory result = acp.execute(
            poolId, 
            address(complexContract), 
            1 ether, 
            abi.encodeWithSignature("complexReturn(uint256)", 42)
        );
        
        (uint256 a, string memory b, bool c) = abi.decode(result, (uint256, string, bool));
        assertEq(a, 42);
        assertEq(b, "hello");
        assertTrue(c);
    }
    
    // ============================================================
    //                      FUZZ TESTS
    // ============================================================
    
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
        
        uint256 received = (alice.balance - aliceBefore) + (bob.balance - bobBefore);
        uint256 total = uint256(amount1) + uint256(amount2);
        
        // Total received should equal total contributed (minus dust)
        assertLe(total - received, 2);
    }
    
    function testFuzz_ProportionalDistribution(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 >= 1000 && amount2 >= 1000);
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
        
        // Cross multiply to check proportionality
        uint256 cross1 = aliceReceived * uint256(amount2);
        uint256 cross2 = bobReceived * uint256(amount1);
        
        uint256 tolerance = (cross1 > cross2 ? cross1 : cross2) / 10000;
        uint256 diff = cross1 > cross2 ? cross1 - cross2 : cross2 - cross1;
        assertLe(diff, tolerance + 1);
    }
    
    function testFuzz_DepositAndDistribute(uint96 contribution, uint96 deposit) public {
        vm.assume(contribution > 0 && deposit > 0);
        vm.assume(uint256(contribution) + uint256(deposit) <= 100 ether);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: contribution}(poolId, alice);
        acp.execute(poolId, controller, contribution, "");
        acp.deposit{value: deposit}(poolId);
        vm.stopPrank();
        
        uint256 aliceBefore = alice.balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        assertEq(alice.balance - aliceBefore, deposit);
    }
}

// ============================================================
//                    HELPER CONTRACTS
// ============================================================

contract SimpleReceiver {
    function receiveAndReturn() external payable returns (uint256) {
        return 42;
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("I always revert");
    }
}

contract RejectingReceiver {
    receive() external payable {
        revert();
    }
}

contract ReentrantAttacker {
    ACP public acp;
    uint256 public poolId;
    uint256 public attackCount;
    
    constructor(address payable _acp) {
        acp = ACP(_acp);
    }
    
    function setPoolId(uint256 _poolId) external {
        poolId = _poolId;
    }
    
    receive() external payable {
        if (attackCount < 3) {
            attackCount++;
            // Try to re-enter distribute
            try acp.distribute(poolId, address(0)) {} catch {}
        }
    }
}

contract TokenReceiver {
    mapping(address => uint256) public balances;
    
    function onTokenReceived(address token, uint256 amount) external {
        balances[token] = amount;
        IERC20(token).transfer(msg.sender, amount);
    }
}

contract ComplexReturnContract {
    function complexReturn(uint256 input) external payable returns (uint256, string memory, bool) {
        return (input, "hello", true);
    }
}

contract FeeOnTransferToken {
    string public name = "Fee Token";
    string public symbol = "FEE";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 public feePercent = 1; // 1% fee
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        uint256 fee = amount * feePercent / 100;
        uint256 netAmount = amount - fee;
        balanceOf[from] -= amount;
        balanceOf[to] += netAmount;
        // Fee is burned
        return true;
    }
}
