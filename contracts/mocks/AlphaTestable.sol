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

/// @notice Simplified router interface for testing (mocks Universal Router behavior)
interface IRouter {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) external returns (uint256 amountOut);
}

/// @title AlphaTestable
/// @notice Coordinated group trading with slippage protection (testable version)
/// @dev Uses simplified router interface instead of V4 Universal Router encoding
contract AlphaTestable {
    using SafeERC20 for IERC20;

    ACP public immutable acp;
    address public immutable router;
    address public immutable weth;

    uint256 public constant MAX_SLIPPAGE_BPS = 1000; // 10% max
    uint256 public constant BPS_DENOMINATOR = 10000;

    enum Status { Funding, Bought, Sold, Expired }

    struct Trade {
        uint256 poolId;
        uint256 threshold;
        uint256 buyTime;
        uint256 sellTime;
        uint256 deadline;
        uint256 tokensHeld;
        uint256 expectedBuyOutput;    // For slippage calc
        uint256 expectedSellOutput;   // For slippage calc
        uint256 maxSlippageBps;       // Per-trade slippage tolerance
        address tokenOut;
        uint24 fee;
        Status status;
    }

    Trade[] public trades;

    event TradeCreated(uint256 indexed tradeId, address tokenOut, uint256 threshold, uint256 maxSlippageBps);
    event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
    event BuyExecuted(uint256 indexed tradeId, uint256 ethSpent, uint256 tokensReceived);
    event SellExecuted(uint256 indexed tradeId, uint256 tokensSold, uint256 ethReceived);
    event ExpectedOutputsSet(uint256 indexed tradeId, uint256 expectedBuy, uint256 expectedSell);

    error InvalidToken();
    error InvalidTiming();
    error InvalidSlippage();
    error TradeClosed();
    error ZeroValue();
    error NotFunding();
    error NotBought();
    error NotSold();
    error TooEarly();
    error ThresholdNotMet();
    error SlippageExceeded();
    error CannotWithdraw();

    constructor(address _acp, address _router, address _weth) {
        acp = ACP(payable(_acp));
        router = _router;
        weth = _weth;
    }

    /// @notice Create a new coordinated trade
    /// @param tokenOut Token to buy
    /// @param threshold Minimum ETH to proceed
    /// @param buyTime When buy can execute
    /// @param sellTime When sell can execute
    /// @param joinDeadline Last moment to join
    /// @param fee Pool fee tier
    /// @param maxSlippageBps Max slippage in basis points (100 = 1%)
    function create(
        address tokenOut,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 joinDeadline,
        uint24 fee,
        uint256 maxSlippageBps
    ) external returns (uint256 tradeId) {
        if (tokenOut == address(0)) revert InvalidToken();
        if (sellTime <= buyTime) revert InvalidTiming();
        if (joinDeadline > buyTime) revert InvalidTiming();
        if (maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidSlippage();

        uint256 poolId = acp.createPool(address(0));
        tradeId = trades.length;

        trades.push(Trade({
            poolId: poolId,
            threshold: threshold,
            buyTime: buyTime,
            sellTime: sellTime,
            deadline: joinDeadline,
            tokensHeld: 0,
            expectedBuyOutput: 0,
            expectedSellOutput: 0,
            maxSlippageBps: maxSlippageBps,
            tokenOut: tokenOut,
            fee: fee,
            status: Status.Funding
        }));

        emit TradeCreated(tradeId, tokenOut, threshold, maxSlippageBps);
    }

    /// @notice Backwards-compatible create without slippage param (defaults to 1%)
    function create(
        address tokenOut,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime,
        uint256 joinDeadline,
        uint24 fee
    ) external returns (uint256 tradeId) {
        if (tokenOut == address(0)) revert InvalidToken();
        if (sellTime <= buyTime) revert InvalidTiming();
        if (joinDeadline > buyTime) revert InvalidTiming();

        uint256 poolId = acp.createPool(address(0));
        tradeId = trades.length;

        trades.push(Trade({
            poolId: poolId,
            threshold: threshold,
            buyTime: buyTime,
            sellTime: sellTime,
            deadline: joinDeadline,
            tokensHeld: 0,
            expectedBuyOutput: 0,
            expectedSellOutput: 0,
            maxSlippageBps: 100, // Default 1%
            tokenOut: tokenOut,
            fee: fee,
            status: Status.Funding
        }));

        emit TradeCreated(tradeId, tokenOut, threshold, 100);
    }

    /// @notice Set expected outputs for slippage calculation (call before execute)
    /// @dev Anyone can call - uses current prices from oracle/frontend
    function setExpectedOutputs(uint256 tradeId, uint256 expectedBuy, uint256 expectedSell) external {
        Trade storage t = trades[tradeId];
        if (t.status != Status.Funding && t.status != Status.Bought) revert TradeClosed();

        t.expectedBuyOutput = expectedBuy;
        t.expectedSellOutput = expectedSell;

        emit ExpectedOutputsSet(tradeId, expectedBuy, expectedSell);
    }

    function join(uint256 tradeId) external payable {
        Trade storage t = trades[tradeId];
        if (t.status != Status.Funding || block.timestamp > t.deadline) revert TradeClosed();
        if (msg.value == 0) revert ZeroValue();

        acp.contribute{value: msg.value}(t.poolId, msg.sender);
        emit Joined(tradeId, msg.sender, msg.value);
    }

    function executeBuy(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        if (t.status != Status.Funding) revert NotFunding();
        if (block.timestamp < t.buyTime) revert TooEarly();

        (,,uint256 total,) = acp.getPoolInfo(t.poolId);
        if (total < t.threshold) revert ThresholdNotMet();

        acp.execute(t.poolId, address(this), total, "");

        IWETH(weth).deposit{value: total}();
        IWETH(weth).approve(router, total);

        // Calculate min output with slippage
        uint256 minOut = 0;
        if (t.expectedBuyOutput > 0) {
            minOut = (t.expectedBuyOutput * (BPS_DENOMINATOR - t.maxSlippageBps)) / BPS_DENOMINATOR;
        }

        uint256 tokensOut = IRouter(router).swap(weth, t.tokenOut, total, minOut, address(this));

        t.tokensHeld = tokensOut;
        t.status = Status.Bought;

        emit BuyExecuted(tradeId, total, tokensOut);
    }

    function executeSell(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        if (t.status != Status.Bought) revert NotBought();
        if (block.timestamp < t.sellTime) revert TooEarly();

        uint256 tokenBalance = IERC20(t.tokenOut).balanceOf(address(this));
        IERC20(t.tokenOut).approve(router, tokenBalance);

        // Calculate min output with slippage
        uint256 minOut = 0;
        if (t.expectedSellOutput > 0) {
            minOut = (t.expectedSellOutput * (BPS_DENOMINATOR - t.maxSlippageBps)) / BPS_DENOMINATOR;
        }

        uint256 wethOut = IRouter(router).swap(t.tokenOut, weth, tokenBalance, minOut, address(this));

        IWETH(weth).withdraw(wethOut);
        acp.deposit{value: wethOut}(t.poolId);

        t.status = Status.Sold;

        emit SellExecuted(tradeId, tokenBalance, wethOut);
    }

    function claim(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        if (t.status != Status.Sold) revert NotSold();
        acp.distribute(t.poolId, address(0));
    }

    function withdraw(uint256 tradeId) external {
        Trade storage t = trades[tradeId];
        if (t.status != Status.Funding || block.timestamp <= t.deadline) revert CannotWithdraw();
        t.status = Status.Expired;
        acp.distribute(t.poolId, address(0));
    }

    // ============ Views ============

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
        (,,uint256 total, uint256 numContributors) = acp.getPoolInfo(t.poolId);
        return (t.tokenOut, t.threshold, t.buyTime, t.sellTime, t.deadline, t.tokensHeld, t.status, total, numContributors);
    }

    function getSlippageInfo(uint256 tradeId) external view returns (
        uint256 maxSlippageBps,
        uint256 expectedBuyOutput,
        uint256 expectedSellOutput
    ) {
        Trade storage t = trades[tradeId];
        return (t.maxSlippageBps, t.expectedBuyOutput, t.expectedSellOutput);
    }

    function getContribution(uint256 tradeId, address contributor) external view returns (uint256) {
        return acp.getContribution(trades[tradeId].poolId, contributor);
    }

    function count() external view returns (uint256) {
        return trades.length;
    }

    receive() external payable {}
}
