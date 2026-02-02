// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ACP - Agent Coordination Pool
 * @notice Pool ETH or ERC-20. Execute calls. Distribute proceeds. That's it.
 * 
 * PATTERN:
 *   1. Wrapper creates pool → becomes controller
 *   2. Users contribute via wrapper
 *   3. Wrapper calls execute() when conditions met
 *   4. Wrapper calls distribute() to pay contributors
 *
 * CONTRIBUTION = VOTE. No governance needed.
 */
contract ACP is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    uint256 public constant MAX_CONTRIBUTORS = 250;
    
    struct Pool {
        address token;              // address(0) = ETH, else ERC-20
        address controller;         // Only controller can execute/distribute
        uint256 totalContributed;
        uint256 balance;            // Current pool balance (tracks spend/receive)
        address[] contributors;
        mapping(address => uint256) contributions;
    }
    
    mapping(uint256 => Pool) internal pools;
    
    // Per-pool token balances for ERC20 distributions
    mapping(uint256 => mapping(address => uint256)) public poolTokenBalances;
    
    uint256 public nextPoolId;
    
    event PoolCreated(uint256 indexed poolId, address indexed controller, address token);
    event Contributed(uint256 indexed poolId, address indexed contributor, uint256 amount);
    event Executed(uint256 indexed poolId, address indexed target, uint256 value, bool success);
    event Distributed(uint256 indexed poolId, address token, uint256 totalAmount);
    event Deposited(uint256 indexed poolId, uint256 amount);
    event TokenDeposited(uint256 indexed poolId, address token, uint256 amount);
    
    error NotController();
    error NotETHPool();
    error NotTokenPool();
    error ZeroValue();
    error InsufficientBalance();
    error TransferFailed();
    error TooManyContributors();
    error ExecutionFailed();
    
    modifier onlyController(uint256 poolId) {
        if (msg.sender != pools[poolId].controller) revert NotController();
        _;
    }
    
    /// @notice Create a new pool. Caller becomes controller.
    /// @param token address(0) for ETH, or ERC-20 address
    function createPool(address token) external returns (uint256 poolId) {
        poolId = nextPoolId++;
        Pool storage p = pools[poolId];
        p.token = token;
        p.controller = msg.sender;
        
        emit PoolCreated(poolId, msg.sender, token);
    }
    
    /// @notice Contribute ETH to a pool. Controller only.
    /// @param poolId The pool to contribute to
    /// @param contributor Address to credit (allows wrapper to attribute correctly)
    function contribute(uint256 poolId, address contributor) external payable onlyController(poolId) {
        Pool storage p = pools[poolId];
        if (p.token != address(0)) revert NotETHPool();
        if (msg.value == 0) revert ZeroValue();
        
        _recordContribution(poolId, contributor, msg.value);
    }
    
    /// @notice Contribute ERC-20 to a pool. Controller only.
    /// @param poolId The pool to contribute to
    /// @param contributor Address to credit
    /// @param amount Amount of tokens to contribute
    function contributeToken(uint256 poolId, address contributor, uint256 amount) external onlyController(poolId) {
        Pool storage p = pools[poolId];
        if (p.token == address(0)) revert NotTokenPool();
        if (amount == 0) revert ZeroValue();
        
        // Handle fee-on-transfer tokens
        uint256 balBefore = IERC20(p.token).balanceOf(address(this));
        IERC20(p.token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(p.token).balanceOf(address(this)) - balBefore;
        
        _recordContribution(poolId, contributor, received);
    }
    
    function _recordContribution(uint256 poolId, address contributor, uint256 amount) internal {
        Pool storage p = pools[poolId];
        
        if (p.contributions[contributor] == 0) {
            if (p.contributors.length >= MAX_CONTRIBUTORS) revert TooManyContributors();
            p.contributors.push(contributor);
        }
        p.contributions[contributor] += amount;
        p.totalContributed += amount;
        p.balance += amount;
        
        emit Contributed(poolId, contributor, amount);
    }
    
    /// @notice Execute an arbitrary call with pool funds. Controller only.
    /// @param poolId Pool to use funds from
    /// @param target Contract to call
    /// @param value ETH/token amount to use
    /// @param data Calldata
    function execute(
        uint256 poolId,
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyController(poolId) returns (bytes memory) {
        Pool storage p = pools[poolId];
        
        uint256 ethValue = 0;
        if (p.token == address(0)) {
            // ETH pool - track spend
            if (p.balance < value) revert InsufficientBalance();
            p.balance -= value;
            ethValue = value;
        } else if (value > 0) {
            // ERC-20 pool - approve target
            IERC20(p.token).safeIncreaseAllowance(target, value);
        }
        
        (bool success, bytes memory result) = target.call{value: ethValue}(data);
        
        emit Executed(poolId, target, value, success);
        
        if (!success) {
            // Bubble up revert reason
            if (result.length > 0) {
                assembly { revert(add(result, 32), mload(result)) }
            }
            revert ExecutionFailed();
        }
        
        return result;
    }
    
    /// @notice Distribute a token to all contributors pro-rata. Controller only.
    /// @param poolId Pool whose contributors receive distribution
    /// @param token Token to distribute (address(0) for ETH)
    function distribute(uint256 poolId, address token) external onlyController(poolId) nonReentrant {
        Pool storage p = pools[poolId];
        
        uint256 balance;
        if (token == address(0)) {
            // For ETH, use tracked pool balance
            balance = p.balance;
            p.balance = 0;
        } else {
            // For ERC-20, use per-pool tracked balance
            balance = poolTokenBalances[poolId][token];
            poolTokenBalances[poolId][token] = 0;
        }
        
        if (balance == 0 || p.totalContributed == 0) return;
        
        // Cache for gas
        uint256 total = p.totalContributed;
        uint256 len = p.contributors.length;
        uint256 totalDistributed;
        
        for (uint256 i = 0; i < len; i++) {
            address c = p.contributors[i];
            uint256 share = (balance * p.contributions[c]) / total;
            
            if (share > 0) {
                if (token == address(0)) {
                    (bool ok,) = c.call{value: share}("");
                    if (!ok) revert TransferFailed();
                } else {
                    IERC20(token).safeTransfer(c, share);
                }
                totalDistributed += share;
            }
        }
        
        emit Distributed(poolId, token, totalDistributed);
    }
    
    /// @notice Deposit ETH back into a pool (e.g., from sale proceeds). Controller only.
    function deposit(uint256 poolId) external payable onlyController(poolId) {
        Pool storage p = pools[poolId];
        if (p.token != address(0)) revert NotETHPool();
        p.balance += msg.value;
        
        emit Deposited(poolId, msg.value);
    }
    
    /// @notice Deposit ERC-20 back into a pool. Controller only.
    /// @param poolId Pool to deposit into
    /// @param token Token to deposit (can be different from pool's contribution token)
    /// @param amount Amount to deposit
    function depositToken(uint256 poolId, address token, uint256 amount) external onlyController(poolId) {
        // Handle fee-on-transfer tokens
        uint256 balBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;
        
        poolTokenBalances[poolId][token] += received;
        
        emit TokenDeposited(poolId, token, received);
    }
    
    // ============ Views ============
    
    function poolCount() external view returns (uint256) {
        return nextPoolId;
    }
    
    function getContributors(uint256 poolId) external view returns (address[] memory) {
        return pools[poolId].contributors;
    }
    
    function getContributorsPaginated(uint256 poolId, uint256 start, uint256 count) external view returns (address[] memory) {
        Pool storage p = pools[poolId];
        uint256 len = p.contributors.length;
        
        if (start >= len) return new address[](0);
        
        uint256 end = start + count;
        if (end > len) end = len;
        
        address[] memory result = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = p.contributors[i];
        }
        return result;
    }
    
    function getContribution(uint256 poolId, address contributor) external view returns (uint256) {
        return pools[poolId].contributions[contributor];
    }
    
    function getPoolBalance(uint256 poolId) external view returns (uint256) {
        return pools[poolId].balance;
    }
    
    function getPoolTokenBalance(uint256 poolId, address token) external view returns (uint256) {
        return poolTokenBalances[poolId][token];
    }
    
    function getPoolInfo(uint256 poolId) external view returns (
        address token,
        address controller,
        uint256 totalContributed,
        uint256 contributorCount
    ) {
        Pool storage p = pools[poolId];
        return (p.token, p.controller, p.totalContributed, p.contributors.length);
    }
    
    // ============ Receive ============
    
    receive() external payable {}
}
