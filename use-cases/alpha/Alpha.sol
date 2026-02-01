// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";

/**
 * @title Alpha
 * @notice Collective trading intelligence. Pool → Buy at T1 → Sell at T2 → Distribute.
 * 
 * FOR AGENTS:
 *   1. Create a trade: "Buy $TOKEN with pooled ETH at time X, sell at time Y"
 *   2. Contribute ETH/USDC (contribution = agreement)
 *   3. When buyTime reached: executeBuy() swaps to target token
 *   4. When sellTime reached: executeSell() swaps back
 *   5. claim() distributes proceeds pro-rata
 *
 * CONTRIBUTION = VOTE. No governance needed.
 */

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

contract Alpha {
    using SafeERC20 for IERC20;
    
    ACP public immutable acp;
    address public immutable swapRouter;
    address public immutable weth;
    
    enum Status { Funding, Bought, Sold, Expired }
    
    struct Trade {
        uint256 poolId;
        address tokenIn;        // Base token (address(0) for ETH)
        address tokenOut;       // Token to buy
        uint24 poolFee;         // DEX pool fee tier
        uint256 threshold;      // Min contribution to execute
        uint256 buyTime;        // When to buy
        uint256 sellTime;       // When to sell
        uint256 deadline;       // Funding deadline
        uint256 amountBought;   // Tokens bought
        Status status;
    }
    
    Trade[] public trades;
    
    event TradeCreated(
        uint256 indexed tradeId, 
        address tokenIn, 
        address tokenOut, 
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime
    );
    event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
    event BuyExecuted(uint256 indexed tradeId, uint256 amountIn, uint256 amountOut);
    event SellExecuted(uint256 indexed tradeId, uint256 amountIn, uint256 amountOut);
    
    constructor(address _acp, address _swapRouter, address _weth) {
        acp = ACP(payable(_acp));
        swapRouter = _swapRouter;
        weth = _weth;
    }
    
    /// @notice Create a new trade opportunity
    function create(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 fundingDeadline
    ) external returns (uint256 tradeId) {
        require(buyTime > block.timestamp, "buyTime passed");
        require(sellTime > buyTime, "sellTime must be after buyTime");
        require(fundingDeadline <= buyTime, "deadline must be <= buyTime");
        require(threshold > 0, "threshold=0");
        
        uint256 poolId = acp.createPool(tokenIn);
        
        tradeId = trades.length;
        trades.push(Trade({
            poolId: poolId,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            poolFee: poolFee,
            threshold: threshold,
            buyTime: buyTime,
            sellTime: sellTime,
            deadline: fundingDeadline,
            amountBought: 0,
            status: Status.Funding
        }));
        
        emit TradeCreated(tradeId, tokenIn, tokenOut, threshold, buyTime, sellTime);
    }
    
    /// @notice Join a trade (contribute ETH)
    function join(uint256 tradeId) external payable {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp <= t.deadline, "deadline passed");
        require(t.tokenIn == address(0), "use joinWithToken");
        require(msg.value > 0, "no value");
        
        acp.contribute{value: msg.value}(t.poolId, msg.sender);
        emit Joined(tradeId, msg.sender, msg.value);
    }
    
    /// @notice Join with ERC-20
    function joinWithToken(uint256 tradeId, uint256 amount) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp <= t.deadline, "deadline passed");
        require(t.tokenIn != address(0), "use join for ETH");
        require(amount > 0, "amount=0");
        
        IERC20(t.tokenIn).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(t.tokenIn).approve(address(acp), amount);
        acp.contributeToken(t.poolId, msg.sender, amount);
        
        emit Joined(tradeId, msg.sender, amount);
    }
    
    /// @notice Execute the buy (when buyTime reached + threshold met)
    function executeBuy(uint256 tradeId, uint256 minAmountOut) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp >= t.buyTime, "too early");
        
        (,,uint256 totalContributed,) = acp.getPoolInfo(t.poolId);
        require(totalContributed >= t.threshold, "threshold not met");
        
        uint256 amountIn = totalContributed;
        
        if (t.tokenIn == address(0)) {
            // ETH pool: Pull ETH from ACP → wrap → swap
            // Use execute to send ETH to this contract
            acp.execute(t.poolId, address(this), amountIn, "");
            
            // Wrap to WETH
            IWETH(weth).deposit{value: amountIn}();
            IWETH(weth).approve(swapRouter, amountIn);
        } else {
            // ERC-20 pool: Pull tokens from ACP
            acp.execute(t.poolId, t.tokenIn, 0, 
                abi.encodeCall(IERC20.transfer, (address(this), amountIn)));
            IERC20(t.tokenIn).approve(swapRouter, amountIn);
        }
        
        // Swap to target token
        address swapTokenIn = t.tokenIn == address(0) ? weth : t.tokenIn;
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: swapTokenIn,
                tokenOut: t.tokenOut,
                fee: t.poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        
        t.amountBought = amountOut;
        t.status = Status.Bought;
        
        emit BuyExecuted(tradeId, amountIn, amountOut);
    }
    
    /// @notice Execute the sell (when sellTime reached)
    function executeSell(uint256 tradeId, uint256 minAmountOut) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Bought, "not bought");
        require(block.timestamp >= t.sellTime, "too early");
        
        address swapTokenOut = t.tokenIn == address(0) ? weth : t.tokenIn;
        
        // Swap back to base token
        IERC20(t.tokenOut).approve(swapRouter, t.amountBought);
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: t.tokenOut,
                tokenOut: swapTokenOut,
                fee: t.poolFee,
                recipient: address(this),
                amountIn: t.amountBought,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        
        if (t.tokenIn == address(0)) {
            // Unwrap WETH → ETH, deposit back to ACP
            IWETH(weth).withdraw(amountOut);
            acp.deposit{value: amountOut}(t.poolId);
        } else {
            // Transfer tokens back to ACP
            IERC20(t.tokenIn).approve(address(acp), amountOut);
            acp.depositToken(t.poolId, amountOut);
        }
        
        t.status = Status.Sold;
        
        emit SellExecuted(tradeId, t.amountBought, amountOut);
    }
    
    /// @notice Claim your share of proceeds
    function claim(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Sold, "not sold");
        
        acp.distribute(t.poolId, t.tokenIn);
    }
    
    /// @notice Withdraw if funding expired
    function withdraw(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp > t.deadline, "not expired");
        
        t.status = Status.Expired;
        acp.distribute(t.poolId, t.tokenIn);
    }
    
    // ============ Views ============
    
    function getTradeInfo(uint256 tradeId) external view returns (
        address tokenIn,
        address tokenOut,
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
            t.tokenIn, t.tokenOut, t.threshold, 
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
