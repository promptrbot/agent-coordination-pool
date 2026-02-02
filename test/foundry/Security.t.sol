// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/ACP.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/AlphaTestable.sol";

// ============================================================
//                    MALICIOUS CONTRACTS
// ============================================================

/// @dev Attempts reentrancy on distribute()
contract ReentrantAttacker {
    ACP public acp;
    uint256 public poolId;
    uint256 public attackCount;
    uint256 public maxAttacks;
    
    constructor(address _acp) {
        acp = ACP(payable(_acp));
    }
    
    function setup(uint256 _poolId, uint256 _maxAttacks) external {
        poolId = _poolId;
        maxAttacks = _maxAttacks;
        attackCount = 0;
    }
    
    receive() external payable {
        attackCount++;
        if (attackCount < maxAttacks) {
            // Try to reenter
            try acp.distribute(poolId, address(0)) {
                // If this succeeds, reentrancy protection failed
            } catch {
                // Expected - reentrancy guard blocked it
            }
        }
    }
}

/// @dev Contract that always reverts on receive
contract RevertingReceiver {
    receive() external payable {
        revert("I reject your ETH");
    }
}

/// @dev Gas-consuming receiver
contract GasGuzzler {
    uint256 public counter;
    
    receive() external payable {
        // Consume a lot of gas
        for (uint i = 0; i < 1000; i++) {
            counter++;
        }
    }
}

/// @dev Fee-on-transfer token (1% fee)
contract FeeOnTransferToken is MockERC20 {
    constructor() MockERC20("FeeToken", "FEE", 18) {}
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = amount / 100; // 1% fee
        uint256 netAmount = amount - fee;
        
        _burn(from, fee); // Fee goes to burn
        return super.transferFrom(from, to, netAmount);
    }
}

// ============================================================
//                    SECURITY TESTS
// ============================================================

contract SecurityTest is Test {
    ACP public acp;
    MockERC20 public token;
    
    address public controller = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public attacker = address(5);
    
    function setUp() public {
        acp = new ACP();
        token = new MockERC20("Test", "TEST", 18);
        
        vm.deal(controller, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(attacker, 1000 ether);
    }
    
    // ============================================================
    //            FIX #1: REENTRANCY GUARD ON DISTRIBUTE
    // ============================================================
    
    function test_Security_ReentrancyGuard_BlocksAttack() public {
        ReentrantAttacker attackerContract = new ReentrantAttacker(address(acp));
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Attacker contributes via controller
        vm.startPrank(controller);
        acp.contribute{value: 5 ether}(poolId, address(attackerContract));
        acp.contribute{value: 5 ether}(poolId, alice);
        vm.stopPrank();
        
        attackerContract.setup(poolId, 5);
        
        uint256 aliceBefore = alice.balance;
        uint256 attackerBefore = address(attackerContract).balance;
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Alice got her share
        assertEq(alice.balance - aliceBefore, 5 ether);
        
        // Attacker got exactly their share, no more
        assertEq(address(attackerContract).balance - attackerBefore, 5 ether);
        
        // Attacker's reentry attempts were blocked (or had no effect)
        assertGt(attackerContract.attackCount(), 0, "Attack was attempted");
    }
    
    function test_Security_ReentrancyGuard_CantDistributeTwice() public {
        ReentrantAttacker attackerContract = new ReentrantAttacker(address(acp));
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 10 ether}(poolId, address(attackerContract));
        vm.stopPrank();
        
        attackerContract.setup(poolId, 10);
        
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Pool balance is now zero
        assertEq(acp.getPoolBalance(poolId), 0);
        
        // Second distribute has nothing
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        
        // Attacker only got original share
        assertEq(address(attackerContract).balance, 10 ether);
    }
    
    // ============================================================
    //            FIX #2: MAX CONTRIBUTORS LIMIT
    // ============================================================
    
    function test_Security_MaxContributors_Enforced() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Add MAX_CONTRIBUTORS
        uint256 max = acp.MAX_CONTRIBUTORS();
        
        vm.startPrank(controller);
        for (uint256 i = 0; i < max; i++) {
            address contributor = address(uint160(1000 + i));
            acp.contribute{value: 0.01 ether}(poolId, contributor);
        }
        vm.stopPrank();
        
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, max);
        
        // Next contribution should revert
        address oneMore = address(uint160(1000 + max));
        vm.prank(controller);
        vm.expectRevert(ACP.TooManyContributors.selector);
        acp.contribute{value: 0.01 ether}(poolId, oneMore);
    }
    
    function test_Security_MaxContributors_SameAddressOK() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        uint256 max = acp.MAX_CONTRIBUTORS();
        
        // Fill to max
        vm.startPrank(controller);
        for (uint256 i = 0; i < max; i++) {
            address contributor = address(uint160(1000 + i));
            acp.contribute{value: 0.01 ether}(poolId, contributor);
        }
        
        // Same contributor can add more
        address existingContributor = address(uint160(1000));
        acp.contribute{value: 0.01 ether}(poolId, existingContributor);
        vm.stopPrank();
        
        // Count unchanged
        (,,, uint256 count) = acp.getPoolInfo(poolId);
        assertEq(count, max);
        
        // But contribution increased
        assertEq(acp.getContribution(poolId, existingContributor), 0.02 ether);
    }
    
    function test_Security_MaxContributors_DistributionSucceeds() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        uint256 max = acp.MAX_CONTRIBUTORS();
        
        vm.startPrank(controller);
        for (uint256 i = 0; i < max; i++) {
            address contributor = address(uint160(1000 + i));
            vm.deal(contributor, 0);
            acp.contribute{value: 0.01 ether}(poolId, contributor);
        }
        vm.stopPrank();
        
        uint256 gasBefore = gasleft();
        vm.prank(controller);
        acp.distribute(poolId, address(0));
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should complete within block gas limit
        assertLt(gasUsed, 30_000_000, "Distribution should complete within block gas limit");
        
        // All contributors got their share
        address firstContributor = address(uint160(1000));
        assertEq(firstContributor.balance, 0.01 ether);
    }
    
    // ============================================================
    //            FIX #3: PER-POOL TOKEN BALANCE TRACKING
    // ============================================================
    
    function test_Security_PerPoolTokenTracking_Isolated() public {
        vm.startPrank(controller);
        uint256 pool1 = acp.createPool(address(0));
        uint256 pool2 = acp.createPool(address(0));
        
        acp.contribute{value: 10 ether}(pool1, alice);
        acp.contribute{value: 10 ether}(pool2, bob);
        vm.stopPrank();
        
        // Deposit tokens to each pool
        token.mint(controller, 200 ether);
        vm.startPrank(controller);
        token.approve(address(acp), 200 ether);
        acp.depositToken(pool1, address(token), 100 ether);
        acp.depositToken(pool2, address(token), 100 ether);
        vm.stopPrank();
        
        // Verify isolated balances
        assertEq(acp.getPoolTokenBalance(pool1, address(token)), 100 ether);
        assertEq(acp.getPoolTokenBalance(pool2, address(token)), 100 ether);
        
        // Distribute pool1
        vm.prank(controller);
        acp.distribute(pool1, address(token));
        
        // Alice got pool1's tokens
        assertEq(token.balanceOf(alice), 100 ether);
        
        // Pool2's tokens untouched
        assertEq(acp.getPoolTokenBalance(pool2, address(token)), 100 ether);
        
        // Distribute pool2
        vm.prank(controller);
        acp.distribute(pool2, address(token));
        
        // Bob got pool2's tokens
        assertEq(token.balanceOf(bob), 100 ether);
    }
    
    function test_Security_PerPoolTokenTracking_MultipleTokens() public {
        MockERC20 token2 = new MockERC20("Token2", "TK2", 18);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        // Deposit two different tokens
        token.mint(controller, 100 ether);
        token2.mint(controller, 200 ether);
        
        vm.startPrank(controller);
        token.approve(address(acp), 100 ether);
        token2.approve(address(acp), 200 ether);
        acp.depositToken(poolId, address(token), 100 ether);
        acp.depositToken(poolId, address(token2), 200 ether);
        vm.stopPrank();
        
        // Verify separate tracking
        assertEq(acp.getPoolTokenBalance(poolId, address(token)), 100 ether);
        assertEq(acp.getPoolTokenBalance(poolId, address(token2)), 200 ether);
        
        // Distribute first token
        vm.prank(controller);
        acp.distribute(poolId, address(token));
        
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(acp.getPoolTokenBalance(poolId, address(token)), 0);
        assertEq(acp.getPoolTokenBalance(poolId, address(token2)), 200 ether);
        
        // Distribute second token
        vm.prank(controller);
        acp.distribute(poolId, address(token2));
        
        assertEq(token2.balanceOf(alice), 200 ether);
    }
    
    // ============================================================
    //            FIX #4: FEE-ON-TRANSFER TOKEN HANDLING
    // ============================================================
    
    function test_Security_FeeOnTransfer_CorrectAccounting() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.mint(controller, 100 ether);
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(feeToken));
        
        vm.startPrank(controller);
        feeToken.approve(address(acp), 100 ether);
        acp.contributeToken(poolId, alice, 100 ether);
        vm.stopPrank();
        
        // Only 99 arrived (1% fee burned)
        assertEq(feeToken.balanceOf(address(acp)), 99 ether);
        
        // Contribution correctly recorded as received amount
        assertEq(acp.getContribution(poolId, alice), 99 ether);
        assertEq(acp.getPoolBalance(poolId), 99 ether);
    }
    
    function test_Security_FeeOnTransfer_DistributionWorks() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(feeToken));
        
        // Two contributors
        feeToken.mint(controller, 200 ether);
        vm.startPrank(controller);
        feeToken.approve(address(acp), 200 ether);
        acp.contributeToken(poolId, alice, 100 ether);  // 99 arrives
        acp.contributeToken(poolId, bob, 100 ether);    // 99 arrives
        vm.stopPrank();
        
        // Total: 198 tokens, contributions: 99 + 99 = 198
        assertEq(feeToken.balanceOf(address(acp)), 198 ether);
        assertEq(acp.getContribution(poolId, alice), 99 ether);
        assertEq(acp.getContribution(poolId, bob), 99 ether);
        
        // Deposit more tokens for distribution
        feeToken.mint(controller, 100 ether);
        vm.startPrank(controller);
        feeToken.approve(address(acp), 100 ether);
        acp.depositToken(poolId, address(feeToken), 100 ether);  // 99 arrives
        vm.stopPrank();
        
        assertEq(acp.getPoolTokenBalance(poolId, address(feeToken)), 99 ether);
        
        // Distribute - each gets 50% of 99 = 49.5, rounded down
        vm.prank(controller);
        acp.distribute(poolId, address(feeToken));
        
        // Each contributor gets half (49 ether each due to rounding)
        assertEq(feeToken.balanceOf(alice), 49 ether);
        assertEq(feeToken.balanceOf(bob), 49 ether);
    }
    
    function test_Security_FeeOnTransfer_DepositToken() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.prank(controller);
        acp.contribute{value: 10 ether}(poolId, alice);
        
        // Deposit fee token
        feeToken.mint(controller, 100 ether);
        vm.startPrank(controller);
        feeToken.approve(address(acp), 100 ether);
        acp.depositToken(poolId, address(feeToken), 100 ether);
        vm.stopPrank();
        
        // Only 99 tracked
        assertEq(acp.getPoolTokenBalance(poolId, address(feeToken)), 99 ether);
    }
    
    // ============================================================
    //            FIX #5: REVERTING RECEIVER HANDLING
    // ============================================================
    
    function test_Security_RevertingReceiver_FailsDistribution() public {
        RevertingReceiver badReceiver = new RevertingReceiver();
        
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        vm.startPrank(controller);
        acp.contribute{value: 5 ether}(poolId, address(badReceiver));
        acp.contribute{value: 5 ether}(poolId, alice);
        vm.stopPrank();
        
        // Distribution fails because one receiver reverts
        vm.prank(controller);
        vm.expectRevert(ACP.TransferFailed.selector);
        acp.distribute(poolId, address(0));
    }
    
    // ============================================================
    //            ALPHA: SLIPPAGE PROTECTION TESTS
    // ============================================================
    
    function test_Security_Alpha_SlippageLimit() public {
        // Deploy mock router and weth
        MockRouter router = new MockRouter();
        MockWETH weth = new MockWETH();
        
        AlphaTestable alpha = new AlphaTestable(address(acp), address(router), address(weth));
        
        // Max slippage is 10% (1000 bps)
        vm.expectRevert(AlphaTestable.InvalidSlippage.selector);
        alpha.create(
            address(token),
            1 ether,
            block.timestamp + 1 hours,
            block.timestamp + 1 days,
            block.timestamp + 30 minutes,
            200,
            1001  // > 10%
        );
    }
    
    function test_Security_Alpha_CustomSlippage() public {
        MockRouter router = new MockRouter();
        MockWETH weth = new MockWETH();
        
        AlphaTestable alpha = new AlphaTestable(address(acp), address(router), address(weth));
        
        // Create with 5% slippage
        uint256 tradeId = alpha.create(
            address(token),
            1 ether,
            block.timestamp + 1 hours,
            block.timestamp + 1 days,
            block.timestamp + 30 minutes,
            200,
            500  // 5%
        );
        
        (uint256 maxSlippage,,) = alpha.getSlippageInfo(tradeId);
        assertEq(maxSlippage, 500);
    }
    
    function test_Security_Alpha_DefaultSlippage() public {
        MockRouter router = new MockRouter();
        MockWETH weth = new MockWETH();
        
        AlphaTestable alpha = new AlphaTestable(address(acp), address(router), address(weth));
        
        // Create without slippage param (uses 6-param version)
        uint256 tradeId = alpha.create(
            address(token),
            1 ether,
            block.timestamp + 1 hours,
            block.timestamp + 1 days,
            block.timestamp + 30 minutes,
            200
        );
        
        (uint256 maxSlippage,,) = alpha.getSlippageInfo(tradeId);
        assertEq(maxSlippage, 100);  // Default 1%
    }
    
    // ============================================================
    //            PAGINATION TESTS
    // ============================================================
    
    function test_Security_Pagination_GetContributors() public {
        vm.prank(controller);
        uint256 poolId = acp.createPool(address(0));
        
        // Add 10 contributors
        vm.startPrank(controller);
        for (uint256 i = 0; i < 10; i++) {
            address contributor = address(uint160(1000 + i));
            acp.contribute{value: 0.1 ether}(poolId, contributor);
        }
        vm.stopPrank();
        
        // Get first 5
        address[] memory first5 = acp.getContributorsPaginated(poolId, 0, 5);
        assertEq(first5.length, 5);
        assertEq(first5[0], address(uint160(1000)));
        assertEq(first5[4], address(uint160(1004)));
        
        // Get next 5
        address[] memory next5 = acp.getContributorsPaginated(poolId, 5, 5);
        assertEq(next5.length, 5);
        assertEq(next5[0], address(uint160(1005)));
        assertEq(next5[4], address(uint160(1009)));
        
        // Get beyond end
        address[] memory beyondEnd = acp.getContributorsPaginated(poolId, 8, 5);
        assertEq(beyondEnd.length, 2);  // Only 2 left
        
        // Start beyond end
        address[] memory empty = acp.getContributorsPaginated(poolId, 100, 5);
        assertEq(empty.length, 0);
    }
}

// ============================================================
//                    MOCK CONTRACTS
// ============================================================

contract MockRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256) {
        // Simple mock - return amountIn as amountOut
        return params.amountIn;
    }
}

contract MockWETH {
    mapping(address => uint256) public balanceOf;
    
    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }
    
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
    
    function approve(address, uint256) external returns (bool) {
        return true;
    }
    
    receive() external payable {}
}
