// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IRouter {
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
    function exactInputSingle(ExactInputSingleParams calldata) external returns (uint256);
}

/// @title AlphaTestable
/// @notice Alpha with configurable addresses for testing
contract AlphaTestable {
    using SafeERC20 for IERC20;
    
    ACP public immutable acp;
    address public immutable router;
    address public immutable weth;
    
    enum Status { Funding, Bought, Sold, Expired }
    
    struct Trade {
        uint256 poolId;
        address tokenOut;
        uint256 threshold;
        uint256 buyTime;
        uint256 sellTime;
        uint256 deadline;
        int24 tickSpacing;
        uint256 tokensHeld;
        Status status;
    }
    
    Trade[] public trades;
    
    event TradeCreated(uint256 indexed tradeId, address tokenOut, uint256 threshold);
    event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
    event BuyExecuted(uint256 indexed tradeId, uint256 ethSpent, uint256 tokensReceived);
    event SellExecuted(uint256 indexed tradeId, uint256 tokensSold, uint256 ethReceived);
    
    constructor(address _acp, address _router, address _weth) {
        acp = ACP(payable(_acp));
        router = _router;
        weth = _weth;
    }
    
    function create(
        address tokenOut,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 deadline,
        int24 tickSpacing
    ) external returns (uint256 tradeId) {
        require(tokenOut != address(0), "invalid token");
        require(sellTime > buyTime, "sell<=buy");
        require(deadline <= buyTime, "deadline>buy");
        
        uint256 poolId = acp.createPool(address(0));
        tradeId = trades.length;
        
        trades.push(Trade({
            poolId: poolId,
            tokenOut: tokenOut,
            threshold: threshold,
            buyTime: buyTime,
            sellTime: sellTime,
            deadline: deadline,
            tickSpacing: tickSpacing,
            tokensHeld: 0,
            status: Status.Funding
        }));
        
        emit TradeCreated(tradeId, tokenOut, threshold);
    }
    
    function join(uint256 tradeId) external payable {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding && block.timestamp <= t.deadline, "closed");
        require(msg.value > 0, "no value");
        
        acp.contribute{value: msg.value}(t.poolId, msg.sender);
        emit Joined(tradeId, msg.sender, msg.value);
    }
    
    function executeBuy(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp >= t.buyTime, "too early");
        
        (,,uint256 total,) = acp.getPoolInfo(t.poolId);
        require(total >= t.threshold, "threshold not met");
        
        acp.execute(t.poolId, address(this), total, "");
        
        IWETH(weth).deposit{value: total}();
        IWETH(weth).approve(router, total);
        
        uint256 tokensOut = IRouter(router).exactInputSingle(IRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: t.tokenOut,
            tickSpacing: t.tickSpacing,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: total,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
        
        t.tokensHeld = tokensOut;
        t.status = Status.Bought;
        
        emit BuyExecuted(tradeId, total, tokensOut);
    }
    
    function executeSell(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Bought, "not bought");
        require(block.timestamp >= t.sellTime, "too early");
        
        uint256 tokenBalance = IERC20(t.tokenOut).balanceOf(address(this));
        IERC20(t.tokenOut).approve(router, tokenBalance);
        
        uint256 wethOut = IRouter(router).exactInputSingle(IRouter.ExactInputSingleParams({
            tokenIn: t.tokenOut,
            tokenOut: weth,
            tickSpacing: t.tickSpacing,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenBalance,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
        
        IWETH(weth).withdraw(wethOut);
        acp.deposit{value: wethOut}(t.poolId);
        
        t.status = Status.Sold;
        
        emit SellExecuted(tradeId, tokenBalance, wethOut);
    }
    
    function claim(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Sold, "not sold");
        acp.distribute(t.poolId, address(0));
    }
    
    function withdraw(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding && block.timestamp > t.deadline, "cannot");
        t.status = Status.Expired;
        acp.distribute(t.poolId, address(0));
    }
    
    function getTradeInfo(uint256 tradeId) external view returns (
        address tokenOut,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 deadline,
        uint256 tokensHeld,
        Status status,
        uint256 totalContributed,
        uint256 contributorCount
    ) {
        Trade storage t = trades[tradeId];
        (,,uint256 total, uint256 count) = acp.getPoolInfo(t.poolId);
        return (t.tokenOut, t.threshold, t.buyTime, t.sellTime, t.deadline, t.tokensHeld, t.status, total, count);
    }
    
    function getContribution(uint256 tradeId, address contributor) external view returns (uint256) {
        return acp.getContribution(trades[tradeId].poolId, contributor);
    }
    
    function count() external view returns (uint256) {
        return trades.length;
    }
    
    receive() external payable {}
}
