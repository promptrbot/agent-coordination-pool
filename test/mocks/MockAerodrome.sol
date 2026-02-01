// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock Aerodrome SlipStream Router for testing
contract MockAerodrome {
    using SafeERC20 for IERC20;
    
    // Configurable exchange rate: tokenOut per WETH (in basis points, 10000 = 1:1)
    mapping(address => uint256) public exchangeRateBps;
    
    // Track swaps for assertions
    struct SwapRecord {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        address recipient;
    }
    SwapRecord[] public swapHistory;
    
    constructor() {}
    
    /// @notice Set exchange rate for a token (tokenOut per WETH in bps)
    function setExchangeRate(address token, uint256 rateBps) external {
        exchangeRateBps[token] = rateBps;
    }
    
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
    
    /// @notice Mock swap - uses configured exchange rate
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut) {
        // Pull input tokens
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        
        // Calculate output based on exchange rate
        uint256 rate = exchangeRateBps[params.tokenOut];
        if (rate == 0) rate = 10000; // Default 1:1
        
        amountOut = (params.amountIn * rate) / 10000;
        require(amountOut >= params.amountOutMinimum, "slippage");
        
        // Send output tokens (must be pre-funded)
        IERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);
        
        // Record swap
        swapHistory.push(SwapRecord({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            amountOut: amountOut,
            recipient: params.recipient
        }));
    }
    
    /// @notice Get swap count
    function swapCount() external view returns (uint256) {
        return swapHistory.length;
    }
    
    /// @notice Fund the mock with tokens for swaps
    function fund(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
