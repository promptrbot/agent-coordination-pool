// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";

/**
 * @title Launchpad
 * @notice Collective token launches via Clanker v4.
 * 
 * LP FEES: All trading fees from the Uniswap V4 pool go to contributors,
 * not just the creator. Anyone can call claimFees() to distribute accumulated fees.
 */

/// @notice Clanker Fee Locker - claims accumulated LP fees
interface IClankerFeeLocker {
    function claim(address rewardRecipient, address token) external;
    function availableFees(address rewardRecipient, address token) external view returns (uint256, uint256);
}

interface IClanker {
    struct TokenConfig {
        address tokenAdmin;
        string name;
        string symbol;
        bytes32 salt;
        string image;
        string metadata;
        string context;
        uint256 originatingChainId;
    }
    
    struct PoolConfig {
        address hook;
        address pairedToken;
        int24 tickIfToken0IsClanker;
        int24 tickSpacing;
        bytes poolData;
    }
    
    struct LockerConfig {
        address locker;
        address[] rewardAdmins;
        address[] rewardRecipients;
        uint16[] rewardBps;
        int24[] tickLower;
        int24[] tickUpper;
        uint16[] positionBps;
        bytes lockerData;
    }
    
    struct MevModuleConfig {
        address mevModule;
        bytes mevModuleData;
    }
    
    struct ExtensionConfig {
        address extension;
        uint256 msgValue;
        uint16 extensionBps;
        bytes extensionData;
    }
    
    struct DeploymentConfig {
        TokenConfig tokenConfig;
        PoolConfig poolConfig;
        LockerConfig lockerConfig;
        MevModuleConfig mevModuleConfig;
        ExtensionConfig[] extensionConfigs;
    }
    
    function deployToken(DeploymentConfig calldata config) external payable returns (address);
}

contract Launchpad {
    using SafeERC20 for IERC20;
    
    // Clanker v4 addresses (Base mainnet)
    address public constant CLANKER = 0xE85A59c628F7d27878ACeB4bf3b35733630083a9;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant FEE_STATIC_HOOK_V2 = 0xb429d62f8f3bFFb98CdB9569533eA23bF0Ba28CC;
    address public constant LOCKER = 0x63D2DfEA64b3433F4071A98665bcD7Ca14d93496;
    address public constant MEV_MODULE_V2 = 0xebB25BB797D82CB78E1bc70406b13233c0854413;
    address public constant DEVBUY = 0x1331f0788F9c08C8F38D52c7a1152250A9dE00be;
    address public constant FEE_LOCKER = 0xF3622742b1E446D92e45E22923Ef11C2fcD55D68;
    
    int24 public constant DEFAULT_TICK = -230400;
    int24 public constant DEFAULT_TICK_SPACING = 200;
    uint256 public constant CHAIN_ID = 8453;
    
    ACP public immutable acp;
    
    enum Status { Funding, Launched, Expired }
    
    struct Launch {
        uint256 poolId;
        string name;
        string symbol;
        string image;
        uint256 threshold;
        uint256 deadline;
        address token;
        address creator;
        Status status;
    }
    
    Launch[] public launches;
    
    event LaunchCreated(uint256 indexed launchId, string name, string symbol, uint256 threshold);
    event Joined(uint256 indexed launchId, address indexed contributor, uint256 amount);
    event Launched(uint256 indexed launchId, address token, uint256 ethRaised);
    
    constructor(address _acp) {
        acp = ACP(payable(_acp));
    }
    
    function create(
        string calldata name,
        string calldata symbol,
        string calldata image,
        uint256 threshold,
        uint256 deadline
    ) external returns (uint256 launchId) {
        require(bytes(name).length > 0 && bytes(symbol).length > 0, "empty");
        require(threshold > 0 && deadline > block.timestamp, "invalid");
        
        uint256 poolId = acp.createPool(address(0));
        launchId = launches.length;
        
        launches.push(Launch({
            poolId: poolId,
            name: name,
            symbol: symbol,
            image: image,
            threshold: threshold,
            deadline: deadline,
            token: address(0),
            creator: msg.sender,
            status: Status.Funding
        }));
        
        emit LaunchCreated(launchId, name, symbol, threshold);
    }
    
    function join(uint256 launchId) external payable {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding && block.timestamp <= l.deadline, "closed");
        require(msg.value > 0, "no value");
        
        acp.contribute{value: msg.value}(l.poolId, msg.sender);
        emit Joined(launchId, msg.sender, msg.value);
    }
    
    function launch(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding, "not funding");
        
        (,,uint256 totalContributed,) = acp.getPoolInfo(l.poolId);
        require(totalContributed >= l.threshold, "threshold not met");
        
        acp.execute(l.poolId, address(this), totalContributed, "");
        
        address token = _deployViaClanker(l, totalContributed);
        
        l.token = token;
        l.status = Status.Launched;
        
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) IERC20(token).safeTransfer(address(acp), bal);
        
        emit Launched(launchId, token, totalContributed);
    }
    
    function _deployViaClanker(Launch storage l, uint256 ethAmount) internal returns (address) {
        IClanker.DeploymentConfig memory cfg;
        
        // Token config
        cfg.tokenConfig = IClanker.TokenConfig({
            tokenAdmin: l.creator,
            name: l.name,
            symbol: l.symbol,
            salt: bytes32(0),
            image: l.image,
            metadata: "",
            context: '{"interface":"ACP"}',
            originatingChainId: CHAIN_ID
        });
        
        // Pool config
        cfg.poolConfig = IClanker.PoolConfig({
            hook: FEE_STATIC_HOOK_V2,
            pairedToken: WETH,
            tickIfToken0IsClanker: DEFAULT_TICK,
            tickSpacing: DEFAULT_TICK_SPACING,
            poolData: abi.encode(uint256(10000), uint256(10000)) // 1% fees
        });
        
        // Locker config
        cfg.lockerConfig = _buildLockerConfig(l.creator);
        
        // MEV config
        cfg.mevModuleConfig = IClanker.MevModuleConfig({
            mevModule: MEV_MODULE_V2,
            mevModuleData: abi.encode(uint256(666777), uint256(41673), uint256(15))
        });
        
        // DevBuy extension
        cfg.extensionConfigs = _buildExtensions(ethAmount);
        
        return IClanker(CLANKER).deployToken{value: ethAmount}(cfg);
    }
    
    function _buildLockerConfig(address creator) internal view returns (IClanker.LockerConfig memory) {
        address[] memory admins = new address[](1);
        admins[0] = creator;  // Creator can change recipient later if needed
        
        address[] memory recipients = new address[](1);
        recipients[0] = address(this);  // Launchpad receives fees → distributes to all
        
        uint16[] memory bps = new uint16[](1);
        bps[0] = 10000;
        
        int24[] memory tickLower = new int24[](2);
        tickLower[0] = DEFAULT_TICK;
        tickLower[1] = -172800;
        
        int24[] memory tickUpper = new int24[](2);
        tickUpper[0] = -172800;
        tickUpper[1] = 887200;
        
        uint16[] memory posBps = new uint16[](2);
        posBps[0] = 9500;
        posBps[1] = 500;
        
        return IClanker.LockerConfig({
            locker: LOCKER,
            rewardAdmins: admins,
            rewardRecipients: recipients,
            rewardBps: bps,
            tickLower: tickLower,
            tickUpper: tickUpper,
            positionBps: posBps,
            lockerData: abi.encode(uint8(0))
        });
    }
    
    function _buildExtensions(uint256 ethAmount) internal view returns (IClanker.ExtensionConfig[] memory) {
        IClanker.ExtensionConfig[] memory exts = new IClanker.ExtensionConfig[](1);
        
        // DevBuy data - simplified for WETH pair
        exts[0] = IClanker.ExtensionConfig({
            extension: DEVBUY,
            msgValue: ethAmount,
            extensionBps: 0,
            extensionData: abi.encode(
                address(0), address(0), uint24(0), int24(0), address(0), // null poolKey
                uint256(0), // amountOutMin
                address(this) // recipient
            )
        });
        
        return exts;
    }
    
    function claim(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Launched, "not launched");
        acp.distribute(l.poolId, l.token);
    }
    
    function withdraw(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Funding && block.timestamp > l.deadline, "cannot");
        l.status = Status.Expired;
        acp.distribute(l.poolId, address(0));
    }
    
    /// @notice Claim accumulated LP fees and distribute to contributors
    /// @dev Anyone can call this - fees go to all contributors pro-rata
    function claimFees(uint256 launchId) external {
        Launch storage l = launches[launchId];
        require(l.status == Status.Launched, "not launched");
        require(l.token != address(0), "no token");
        
        // Claim fees from Clanker FeeLocker (this contract is the reward recipient)
        IClankerFeeLocker(FEE_LOCKER).claim(address(this), l.token);
        
        // Distribute any WETH fees received
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance > 0) {
            IERC20(WETH).safeTransfer(address(acp), wethBalance);
            acp.distribute(l.poolId, WETH);
        }
        
        // Distribute any token fees received
        uint256 tokenBalance = IERC20(l.token).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(l.token).safeTransfer(address(acp), tokenBalance);
            acp.distribute(l.poolId, l.token);
        }
    }
    
    /// @notice Check available fees for a launch
    function availableFees(uint256 launchId) external view returns (uint256 wethFees, uint256 tokenFees) {
        Launch storage l = launches[launchId];
        if (l.status != Status.Launched || l.token == address(0)) return (0, 0);
        return IClankerFeeLocker(FEE_LOCKER).availableFees(address(this), l.token);
    }
    
    function getLaunchInfo(uint256 launchId) external view returns (
        string memory name, string memory symbol, uint256 threshold,
        uint256 deadline, address token, Status status,
        uint256 totalContributed, uint256 contributorCount
    ) {
        Launch storage l = launches[launchId];
        (,,uint256 total, uint256 numContributors) = acp.getPoolInfo(l.poolId);
        return (l.name, l.symbol, l.threshold, l.deadline, l.token, l.status, total, numContributors);
    }
    
    function getContribution(uint256 launchId, address contributor) external view returns (uint256) {
        return acp.getContribution(launches[launchId].poolId, contributor);
    }
    
    function count() external view returns (uint256) {
        return launches.length;
    }
    
    receive() external payable {}
}
