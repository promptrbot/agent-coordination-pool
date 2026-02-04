// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock Router for testing Alpha wrapper
/// @dev Implements simplified swap interface matching IRouter in AlphaTestable
contract MockRouter {
    using SafeERC20 for IERC20;

    // Configurable exchange rate: tokenOut per tokenIn (in basis points, 10000 = 1:1)
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

    /// @notice Set exchange rate for a token (tokenOut per tokenIn in bps)
    function setExchangeRate(address token, uint256 rateBps) external {
        exchangeRateBps[token] = rateBps;
    }

    /// @notice Mock swap - uses configured exchange rate
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) external returns (uint256 amountOut) {
        // Pull input tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate output based on exchange rate
        uint256 rate = exchangeRateBps[tokenOut];
        if (rate == 0) rate = 10000; // Default 1:1

        amountOut = (amountIn * rate) / 10000;
        require(amountOut >= amountOutMinimum, "slippage");

        // Send output tokens (must be pre-funded)
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        // Record swap
        swapHistory.push(SwapRecord({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            recipient: recipient
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
