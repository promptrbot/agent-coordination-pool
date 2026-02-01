// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";
import "./SimpleToken.sol";

/**
 * @title Launchpad
 * @notice Collective token launches. Pool ETH → Deploy token → Create liquidity → Distribute.
 * 
 * FOR AGENTS:
 *   1. Create a launch: name, symbol, threshold
 *   2. Contribute ETH (contribution = vote + allocation)
 *   3. Threshold met → launch() deploys token + creates pool
 *   4. claim() distributes tokens pro-rata
 *
 * Uses Aerodrome V2 for pool creation.
 */

/// @notice Aerodrome V2 Router interface (Velodrome fork)
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }
    
    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    
    function factory() external view returns (address);
}

interface IAerodromeFactory {
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
}

contract Launchpad {
    using SafeERC20 for IERC20;
    
    // Base mainnet addresses
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address public constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    
    // Token economics
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens
    uint256 public constant LP_PERCENTAGE = 20;      // 20% to liquidity pool
    uint256 public constant DISTRIBUTE_PERCENTAGE = 80; // 80% to contributors
    
    ACP public immutable acp;
    
    enum Status { Funding, Launched, Expired }
    
    struct Launch {
        uint256 poolId;
        string name;
        string symbol;
        uint256 threshold;      // Min ETH to launch
        uint256 deadline;       // Funding deadline
        address token;          // Deployed token (set after launch)
        address lpPool;         // Aerodrome pool (set after launch)
        Status status;
    }
    
    Launch[] public launches;
    
    event LaunchCreated(
        uint256 indexed launchId,
        string name,
        string symbol,
        uint256 threshold,
        uint256 deadline
    );
    event Joined(uint256 indexed launchId, address indexed contributor, uint256 amount);
    event Launched(
        uint256 indexed launchId, 
        address token, 
        address pool,
        uint256 ethLiquidity,
        uint256 tokensToContributors
    );
    
    constructor(address _acp) {
        acp = ACP(payable(_acp));
    }
    
    /// @notice Create a new launch proposal
    function create(
        string calldata name,
        string calldata symbol,
        uint256 threshold,
        uint256 deadline
    ) external returns (uint256 launchId) {
        require(bytes(name).length > 0, "name empty");
        require(bytes(symbol).length > 0, "symbol empty");
        require(threshold > 0, "threshold=0");
        require(deadline > block.timestamp, "deadline passed");
        
        // Create ETH pool in ACP
        uint256 poolId = acp.createPool(address(0));
        
        launchId = launches.length;
        launches.push(Launch({
            poolId: poolId,
            name: name,
            symbol: symbol,
            threshold: threshold,
            deadline: deadline,
            token: address(0),
            lpPool: address(0),
            status: Status.Funding
        }));
        
        emit LaunchCreated(launchId, name, symbol, threshold, deadline);
    }
    
    /// @notice Join a launch by contributing ETH
    function join(uint256 launchId) external payable {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding, "not funding");
        require(block.timestamp <= l.deadline, "deadline passed");
        require(msg.value > 0, "no value");
        
        acp.contribute{value: msg.value}(l.poolId, msg.sender);
        emit Joined(launchId, msg.sender, msg.value);
    }
    
    /// @notice Launch the token (anyone can call when threshold met)
    function launch(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding, "not funding");
        
        (,,uint256 totalContributed,) = acp.getPoolInfo(l.poolId);
        require(totalContributed >= l.threshold, "threshold not met");
        
        // Pull ETH from ACP
        acp.execute(l.poolId, address(this), totalContributed, "");
        
        // 1. Deploy token with full supply to this contract
        SimpleToken token = new SimpleToken(l.name, l.symbol, TOTAL_SUPPLY, address(this));
        
        // 2. Calculate splits
        uint256 tokensForLP = (TOTAL_SUPPLY * LP_PERCENTAGE) / 100;
        uint256 tokensForContributors = TOTAL_SUPPLY - tokensForLP;
        
        // 3. Create pool and add liquidity
        address pool = IAerodromeFactory(AERODROME_FACTORY).getPool(
            address(token), WETH, false
        );
        if (pool == address(0)) {
            pool = IAerodromeFactory(AERODROME_FACTORY).createPool(
                address(token), WETH, false
            );
        }
        
        // 4. Add liquidity (ETH + tokens)
        token.approve(AERODROME_ROUTER, tokensForLP);
        IAerodromeRouter(AERODROME_ROUTER).addLiquidityETH{value: totalContributed}(
            address(token),
            false,              // volatile pair
            tokensForLP,
            tokensForLP * 95 / 100,  // 5% slippage
            totalContributed * 95 / 100,
            address(this),      // LP tokens stay here (locked)
            block.timestamp
        );
        
        // 5. Send remaining tokens to ACP for distribution
        token.transfer(address(acp), tokensForContributors);
        
        l.token = address(token);
        l.lpPool = pool;
        l.status = Status.Launched;
        
        emit Launched(launchId, address(token), pool, totalContributed, tokensForContributors);
    }
    
    /// @notice Claim your token allocation
    function claim(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Launched, "not launched");
        
        acp.distribute(l.poolId, l.token);
    }
    
    /// @notice Withdraw if funding expired
    function withdraw(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding, "not funding");
        require(block.timestamp > l.deadline, "not expired");
        
        l.status = Status.Expired;
        acp.distribute(l.poolId, address(0)); // Return ETH
    }
    
    // ============ Views ============
    
    function getLaunchInfo(uint256 launchId) external view returns (
        string memory name,
        string memory symbol,
        uint256 threshold,
        uint256 deadline,
        address token,
        address lpPool,
        Status status,
        uint256 totalContributed,
        uint256 contributorCount
    ) {
        Launch storage l = launches[launchId];
        (,,uint256 total, uint256 numContributors) = acp.getPoolInfo(l.poolId);
        return (
            l.name, l.symbol, l.threshold, l.deadline,
            l.token, l.lpPool, l.status,
            total, numContributors
        );
    }
    
    function getContribution(uint256 launchId, address contributor) external view returns (uint256) {
        return acp.getContribution(launches[launchId].poolId, contributor);
    }
    
    function getContributors(uint256 launchId) external view returns (address[] memory) {
        return acp.getContributors(launches[launchId].poolId);
    }
    
    function count() external view returns (uint256) {
        return launches.length;
    }
    
    receive() external payable {}
}
