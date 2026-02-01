// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../ACP2.sol";

/**
 * @title Launchpad
 * @notice Collective token launches. Pool ETH → Deploy via Clanker → Distribute tokens.
 * 
 * FOR AGENTS:
 *   1. Create a launch: name, symbol, threshold
 *   2. Contribute ETH (contribution = vote + allocation)
 *   3. Threshold met → launch() deploys token via Clanker
 *   4. claim() distributes launched tokens pro-rata
 *
 * CONTRIBUTION = VOTE. Popular ideas get funded.
 */

/// @notice Interface for Clanker token factory (simplified)
interface IClanker {
    /// @notice Deploy a new token with initial liquidity
    /// @return tokenAddress The deployed token address
    function deployToken(
        string calldata name,
        string calldata symbol,
        string calldata image,
        string calldata description
    ) external payable returns (address tokenAddress);
}

contract Launchpad {
    using SafeERC20 for IERC20;
    
    ACP2 public immutable acp;
    address public immutable clanker;
    
    enum Status { Funding, Launched, Expired }
    
    struct Launch {
        uint256 poolId;         // ACP pool ID
        string name;
        string symbol;
        string image;           // IPFS hash or URL
        string description;
        uint256 threshold;      // Min ETH to launch
        uint256 deadline;       // Funding deadline
        address token;          // Deployed token (set after launch)
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
    event Launched(uint256 indexed launchId, address token, uint256 liquidity);
    event Claimed(uint256 indexed launchId, address indexed contributor, uint256 amount);
    
    constructor(address _acp, address _clanker) {
        acp = ACP2(payable(_acp));
        clanker = _clanker;
    }
    
    /// @notice Create a new launch proposal
    function create(
        string calldata name,
        string calldata symbol,
        string calldata image,
        string calldata description,
        uint256 threshold,
        uint256 deadline
    ) external returns (uint256 launchId) {
        require(bytes(name).length > 0, "name empty");
        require(bytes(symbol).length > 0, "symbol empty");
        require(threshold > 0, "threshold=0");
        require(deadline > block.timestamp, "deadline passed");
        
        // Create ACP pool for ETH
        uint256 poolId = acp.createPool(address(0));
        
        launchId = launches.length;
        launches.push(Launch({
            poolId: poolId,
            name: name,
            symbol: symbol,
            image: image,
            description: description,
            threshold: threshold,
            deadline: deadline,
            token: address(0),
            status: Status.Funding
        }));
        
        emit LaunchCreated(launchId, name, symbol, threshold, deadline);
    }
    
    /// @notice Join a launch (contribute ETH)
    function join(uint256 launchId) external payable {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding, "not funding");
        require(block.timestamp <= l.deadline, "deadline passed");
        require(msg.value > 0, "no value");
        
        acp.contribute{value: msg.value}(l.poolId, msg.sender);
        emit Joined(launchId, msg.sender, msg.value);
    }
    
    /// @notice Launch the token (when threshold met)
    function launch(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding, "not funding");
        
        (,,uint256 totalContributed,) = acp.getPoolInfo(l.poolId);
        require(totalContributed >= l.threshold, "threshold not met");
        
        // Deploy token via Clanker with pooled ETH as liquidity
        address token = IClanker(clanker).deployToken{value: totalContributed}(
            l.name,
            l.symbol,
            l.image,
            l.description
        );
        
        l.token = token;
        l.status = Status.Launched;
        
        emit Launched(launchId, token, totalContributed);
    }
    
    /// @notice Claim your token allocation
    function claim(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Launched, "not launched");
        require(l.token != address(0), "no token");
        
        // Distribute tokens via ACP
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
        Status status,
        uint256 totalContributed,
        uint256 contributorCount
    ) {
        Launch storage l = launches[launchId];
        (,,uint256 total, uint256 numContributors) = acp.getPoolInfo(l.poolId);
        return (
            l.name, l.symbol, l.threshold, l.deadline,
            l.token, l.status, total, numContributors
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
