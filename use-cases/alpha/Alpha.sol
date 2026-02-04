// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";

/**
 * @title Alpha
 * @notice Collective trading. Pool -> Buy at T1 -> Sell at T2 -> Distribute.
 *
 * FOR AGENTS:
 *   1. Create a trade: "Buy $TOKEN with pooled ETH at time X, sell at time Y"
 *   2. Contribute ETH (contribution = agreement)
 *   3. When buyTime reached: executeBuy() swaps to target token
 *   4. When sellTime reached: executeSell() swaps back
 *   5. claim() distributes proceeds pro-rata
 *
 * Uses Uniswap V4 Universal Router for swaps (generic, works with any V4 pool).
 * Clanker tokens, standard pairs, custom hooks - all supported.
 */

/// @notice Minimal interface for Uniswap V4 Universal Router
/// @dev The Universal Router uses encoded commands + inputs pattern
interface IUniversalRouter {
    /// @notice Executes encoded commands along with provided inputs
    /// @param commands A set of concatenated commands, each 1 byte
    /// @param inputs An array of byte strings containing abi-encoded inputs for each command
    /// @param deadline The deadline by which the transaction must be executed
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/// @notice Uniswap V4 hook interface (can be address(0) for hookless pools)
interface IHooks {}

/// @notice PoolKey identifies a V4 pool
struct PoolKey {
    address currency0;      // Lower address token (sorted)
    address currency1;      // Higher address token (sorted)
    uint24 fee;             // Pool fee
    int24 tickSpacing;      // Tick spacing
    IHooks hooks;           // Hooks contract (address(0) for none)
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract Alpha {
    using SafeERC20 for IERC20;

    // Base mainnet addresses
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Universal Router command bytes
    uint8 internal constant V4_SWAP = 0x10;

    // V4Router action bytes
    uint8 internal constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 internal constant SETTLE_ALL = 0x09;
    uint8 internal constant TAKE_ALL = 0x01;

    ACP public immutable acp;

    enum Status { Funding, Bought, Sold, Expired }

    struct Trade {
        uint256 poolId;
        address tokenOut;       // Token to buy
        PoolKey poolKey;        // V4 pool identifier
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
        uint24 fee,
        uint256 threshold,
        uint256 buyTime,
        uint256 sellTime
    );
    event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
    event BuyExecuted(uint256 indexed tradeId, uint256 ethIn, uint256 tokensOut);
    event SellExecuted(uint256 indexed tradeId, uint256 tokensIn, uint256 ethOut);

    constructor(address _acp) {
        acp = ACP(payable(_acp));
        // Approve Permit2 to spend WETH (one-time max approval)
        IERC20(WETH).approve(PERMIT2, type(uint256).max);
    }

    /// @notice Create a new trade
    /// @param tokenOut Token to buy
    /// @param poolKey The Uniswap V4 PoolKey identifying the pool to use
    /// @param threshold Minimum ETH to execute
    /// @param buyTime Timestamp when buy executes
    /// @param sellTime Timestamp when sell executes
    /// @param fundingDeadline Deadline to reach threshold
    function create(
        address tokenOut,
        PoolKey calldata poolKey,
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
        trades.push();
        Trade storage t = trades[tradeId];
        t.poolId = poolId;
        t.tokenOut = tokenOut;
        t.poolKey = poolKey;
        t.threshold = threshold;
        t.buyTime = buyTime;
        t.sellTime = sellTime;
        t.deadline = fundingDeadline;
        t.amountBought = 0;
        t.status = Status.Funding;

        emit TradeCreated(tradeId, tokenOut, poolKey.fee, threshold, buyTime, sellTime);
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
    function executeBuy(uint256 tradeId, uint128 minAmountOut) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Funding, "not funding");
        require(block.timestamp >= t.buyTime, "too early");

        (,,uint256 totalContributed,) = acp.getPoolInfo(t.poolId);
        require(totalContributed >= t.threshold, "threshold not met");

        // Pull ETH from ACP
        acp.execute(t.poolId, address(this), totalContributed, "");

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: totalContributed}();

        // Approve Permit2 -> Universal Router spending
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, uint160(totalContributed), uint48(block.timestamp + 60));

        // Determine swap direction: zeroForOne = true if WETH is currency0
        bool zeroForOne = t.poolKey.currency0 == WETH;

        // Build V4 swap via Universal Router
        uint256 balanceBefore = IERC20(t.tokenOut).balanceOf(address(this));
        _executeV4Swap(t.poolKey, zeroForOne, uint128(totalContributed), minAmountOut);
        uint256 amountOut = IERC20(t.tokenOut).balanceOf(address(this)) - balanceBefore;

        t.amountBought = amountOut;
        t.status = Status.Bought;

        emit BuyExecuted(tradeId, totalContributed, amountOut);
    }

    /// @notice Execute the sell (anyone can call when conditions met)
    function executeSell(uint256 tradeId, uint128 minAmountOut) external {
        Trade storage t = trades[tradeId];
        require(t.status == Status.Bought, "not bought");
        require(block.timestamp >= t.sellTime, "too early");

        // Approve Permit2 -> Universal Router spending for tokenOut
        IERC20(t.tokenOut).approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(t.tokenOut, UNIVERSAL_ROUTER, uint160(t.amountBought), uint48(block.timestamp + 60));

        // Swap direction is reverse: if WETH was currency0, now we go oneForZero
        bool zeroForOne = t.poolKey.currency0 == t.tokenOut;

        uint256 wethBefore = IWETH(WETH).balanceOf(address(this));
        _executeV4Swap(t.poolKey, zeroForOne, uint128(t.amountBought), minAmountOut);
        uint256 wethOut = IWETH(WETH).balanceOf(address(this)) - wethBefore;

        // Unwrap WETH -> ETH
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

    // ============ Internal ============

    /// @dev Encode and execute a V4 exact-input-single swap through Universal Router
    function _executeV4Swap(
        PoolKey storage poolKey,
        bool zeroForOne,
        uint128 amountIn,
        uint128 amountOutMinimum
    ) internal {
        // Encode V4Router actions: SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL
        bytes memory actions = abi.encodePacked(
            SWAP_EXACT_IN_SINGLE,
            SETTLE_ALL,
            TAKE_ALL
        );

        // Determine input/output currencies
        address inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        address outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        // Encode params for each action
        bytes[] memory params = new bytes[](3);

        // Action 0: SWAP_EXACT_IN_SINGLE params (IV4Router.ExactInputSingleParams)
        params[0] = abi.encode(
            poolKey.currency0,
            poolKey.currency1,
            poolKey.fee,
            poolKey.tickSpacing,
            poolKey.hooks,
            zeroForOne,
            amountIn,
            amountOutMinimum,
            bytes("") // hookData
        );

        // Action 1: SETTLE_ALL (inputCurrency, maxAmount)
        params[1] = abi.encode(inputCurrency, amountIn);

        // Action 2: TAKE_ALL (outputCurrency, minAmount)
        params[2] = abi.encode(outputCurrency, amountOutMinimum);

        // Wrap into Universal Router command
        bytes memory commands = abi.encodePacked(V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 60);
    }

    // ============ Views ============

    function getTradeInfo(uint256 tradeId) external view returns (
        address tokenOut,
        uint24 fee,
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
            t.tokenOut, t.poolKey.fee, t.threshold,
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
