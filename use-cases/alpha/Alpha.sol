// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";

/**
 * @title Alpha
 * @notice Collective trading. Pool → Buy at T1 → Sell at T2 → Distribute.
 * 
 * FOR AGENTS:
 *   1. Create a trade: "Buy $TOKEN with pooled ETH at time X, sell at time Y"
 *   2. Contribute ETH (contribution = agreement)
 *   3. When buyTime reached: executeBuy() swaps to target token
 *   4. When sellTime reached: executeSell() swaps back
 *   5. claim() distributes proceeds pro-rata
 *
 * Uses Aerodrome SlipStream (concentrated liquidity) for swaps.
 */

/// @notice Aerodrome SlipStream Router interface
interface IAerodromeRouter {
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
    
    function exactInputSingle(ExactInputSingleParams calldata params) 
        external payable returns (uint256 amountOut);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Alpha {
    using SafeERC20 for IERC20;
    
    // Base mainnet addresses
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant AERODROME_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    
    // Common tick spacings
    int24 public constant TICK_SPACING_LOW = 50;     // 0.5% fee tier
    int24 public constant TICK_SPACING_MEDIUM = 100; // 1% fee tier
    int24 public constant TICK_SPACING_HIGH = 200;   // 2% fee tier
    
    ACP public immutable acp;
    
    enum Status { Funding, Bought, Sold, Expired }
    
    struct Trade {
        uint256 poolId;
        address tokenOut;       // Token to buy
        int24 tickSpacing;      // Aerodrome pool tick spacing
        uint256 threshold;      // Min ETH to execute
        uint256 buyTime;        // When to buy
        uint256 sellTime;       // When to sell
        uint256 deadline;       // Funding deadline
        uint256 amountBought;   // Tokens bought
        Status status;
    }
    
    Trade[] public trades;
    
    event TradeCreated(
        uint256 indexed tradeId, 
        address tokenOut, 
        int24 tickSpacing,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime
    );
    event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
    event BuyExecuted(uint256 indexed tradeId, uint256 ethIn, uint256 tokensOut);
    event SellExecuted(uint256 indexed tradeId, uint256 tokensIn, uint256 ethOut);
    
    constructor(address _acp) {
        acp = ACP(payable(_acp));
    }
    
    /// @notice Create a new trade
    /// @param tokenOut Token to buy
    /// @param tickSpacing Aerodrome pool tick spacing (50, 100, or 200)
    /// @param threshold Minimum ETH to execute
    /// @param buyTime Timestamp when buy executes
    /// @param sellTime Timestamp when sell executes
    /// @param fundingDeadline Deadline to reach threshold
    function create(
        address tokenOut,
        int24 tickSpacing,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 fundingDeadline
    ) external returns (uint256 tradeId) {
        require(tokenOut != address(0), "invalid token");
        require(buyTime > block.timestamp, "buyTime passed");
        require(sellTime > buyTime, "sellTime must be after buyTime");
        require(fundingDeadline <= buyTime, "deadline must be <= buyTime");
        require(threshold > 0, "threshold=0");
        
        // Create ETH pool in ACP
        uint256 poolId = acp.createPool(address(0));
        
        tradeId = trades.length;
        trades.push(Trade({
            poolId: poolId,
            tokenOut: tokenOut,
            tickSpacing: tickSpacing,
            threshold: threshold,
            buyTime: buyTime,
            sellTime: sellTime,
            deadline: fundingDeadline,
            amountBought: 0,
            status: Status.Funding
        }));
        
        emit TradeCreated(tradeId, tokenOut, tickSpacing, threshold, buyTime, sellTime);
    }
    
    /// @notice Join a trade by contributing ETH
    function join(uint256 tradeId) external payable {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp <= t.deadline, "deadline passed");
        require(msg.value > 0, "no value");
        
        acp.contribute{value: msg.value}(t.poolId, msg.sender);
        emit Joined(tradeId, msg.sender, msg.value);
    }
    
    /// @notice Execute the buy (anyone can call when conditions met)
    function executeBuy(uint256 tradeId, uint256 minAmountOut) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp >= t.buyTime, "too early");
        
        (,,uint256 totalContributed,) = acp.getPoolInfo(t.poolId);
        require(totalContributed >= t.threshold, "threshold not met");
        
        // Pull ETH from ACP
        acp.execute(t.poolId, address(this), totalContributed, "");
        
        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: totalContributed}();
        IWETH(WETH).approve(AERODROME_ROUTER, totalContributed);
        
        // Swap WETH → tokenOut via Aerodrome
        uint256 amountOut = IAerodromeRouter(AERODROME_ROUTER).exactInputSingle(
            IAerodromeRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: t.tokenOut,
                tickSpacing: t.tickSpacing,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: totalContributed,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        
        t.amountBought = amountOut;
        t.status = Status.Bought;
        
        emit BuyExecuted(tradeId, totalContributed, amountOut);
    }
    
    /// @notice Execute the sell (anyone can call when conditions met)
    function executeSell(uint256 tradeId, uint256 minAmountOut) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Bought, "not bought");
        require(block.timestamp >= t.sellTime, "too early");
        
        // Approve and swap tokenOut → WETH
        IERC20(t.tokenOut).approve(AERODROME_ROUTER, t.amountBought);
        
        uint256 wethOut = IAerodromeRouter(AERODROME_ROUTER).exactInputSingle(
            IAerodromeRouter.ExactInputSingleParams({
                tokenIn: t.tokenOut,
                tokenOut: WETH,
                tickSpacing: t.tickSpacing,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: t.amountBought,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        
        // Unwrap WETH → ETH
        IWETH(WETH).withdraw(wethOut);
        
        // Deposit ETH back to ACP for distribution
        acp.deposit{value: wethOut}(t.poolId);
        
        t.status = Status.Sold;
        
        emit SellExecuted(tradeId, t.amountBought, wethOut);
    }
    
    /// @notice Claim your share of proceeds
    function claim(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Sold, "not sold");
        
        acp.distribute(t.poolId, address(0));
    }
    
    /// @notice Withdraw if funding expired
    function withdraw(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp > t.deadline, "not expired");
        
        t.status = Status.Expired;
        acp.distribute(t.poolId, address(0));
    }
    
    // ============ Views ============
    
    function getTradeInfo(uint256 tradeId) external view returns (
        address tokenOut,
        int24 tickSpacing,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 deadline,
        uint256 amountBought,
        Status status,
        uint256 totalContributed,
        uint256 contributorCount
    ) {
        Trade storage t = trades[tradeId];
        (,,uint256 total, uint256 numContributors) = acp.getPoolInfo(t.poolId);
        return (
            t.tokenOut, t.tickSpacing, t.threshold, 
            t.buyTime, t.sellTime, t.deadline,
            t.amountBought, t.status,
            total, numContributors
        );
    }
    
    function getContribution(uint256 tradeId, address contributor) external view returns (uint256) {
        return acp.getContribution(trades[tradeId].poolId, contributor);
    }
    
    function count() external view returns (uint256) {
        return trades.length;
    }
    
    receive() external payable {}
}
