// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/ACP.sol";

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

/// @title LaunchpadTestable
/// @notice Coordinated token launches via Clanker
contract LaunchpadTestable {
    using SafeERC20 for IERC20;
    
    address public clanker;
    address public weth;
    address public feeLocker;
    
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
    
    event LaunchCreated(uint256 indexed launchId, string name, string symbol, uint256 threshold, address creator);
    event Joined(uint256 indexed launchId, address indexed contributor, uint256 amount);
    event Launched(uint256 indexed launchId, address token, uint256 ethRaised);
    event Withdrawn(uint256 indexed launchId);
    event FeesClaimed(uint256 indexed launchId, uint256 wethAmount, uint256 tokenAmount);
    
    error EmptyNameOrSymbol();
    error InvalidThresholdOrDeadline();
    error LaunchClosed();
    error ZeroValue();
    error NotFunding();
    error NotLaunched();
    error ThresholdNotMet();
    error CannotWithdraw();
    error NoToken();
    
    constructor(address _acp, address _clanker, address _weth, address _feeLocker) {
        acp = ACP(payable(_acp));
        clanker = _clanker;
        weth = _weth;
        feeLocker = _feeLocker;
    }
    
    function create(
        string calldata name,
        string calldata symbol,
        string calldata image,
        uint256 threshold,
        uint256 deadline
    ) external returns (uint256 launchId) {
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert EmptyNameOrSymbol();
        if (threshold == 0 || deadline <= block.timestamp) revert InvalidThresholdOrDeadline();
        
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
        
        emit LaunchCreated(launchId, name, symbol, threshold, msg.sender);
    }
    
    function join(uint256 launchId) external payable {
        Launch storage l = launches[launchId];
        if (l.status != Status.Funding || block.timestamp > l.deadline) revert LaunchClosed();
        if (msg.value == 0) revert ZeroValue();
        
        acp.contribute{value: msg.value}(l.poolId, msg.sender);
        emit Joined(launchId, msg.sender, msg.value);
    }
    
    function launch(uint256 launchId) external {
        Launch storage l = launches[launchId];
        if (l.status != Status.Funding) revert NotFunding();
        
        (,,uint256 totalContributed,) = acp.getPoolInfo(l.poolId);
        if (totalContributed < l.threshold) revert ThresholdNotMet();
        
        acp.execute(l.poolId, address(this), totalContributed, "");
        
        address token = _deployViaClanker(l, launchId, totalContributed);
        
        l.token = token;
        l.status = Status.Launched;
        
        // Transfer received tokens to ACP for distribution
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(token).approve(address(acp), bal);
            acp.depositToken(l.poolId, token, bal);
        }
        
        emit Launched(launchId, token, totalContributed);
    }
    
    function _deployViaClanker(Launch storage l, uint256 launchId, uint256 ethAmount) internal returns (address) {
        IClanker.DeploymentConfig memory cfg;
        
        // Unique salt per launch
        bytes32 salt = keccak256(abi.encodePacked(address(this), launchId, block.timestamp));
        
        cfg.tokenConfig = IClanker.TokenConfig({
            tokenAdmin: l.creator,
            name: l.name,
            symbol: l.symbol,
            salt: salt,
            image: l.image,
            metadata: "",
            context: "{\"interface\":\"ACP\"}",
            originatingChainId: CHAIN_ID
        });
        
        cfg.poolConfig = IClanker.PoolConfig({
            hook: address(0),
            pairedToken: weth,
            tickIfToken0IsClanker: DEFAULT_TICK,
            tickSpacing: DEFAULT_TICK_SPACING,
            poolData: abi.encode(uint256(10000), uint256(10000))
        });
        
        cfg.lockerConfig = _buildLockerConfig(l.creator);
        
        cfg.mevModuleConfig = IClanker.MevModuleConfig({
            mevModule: address(0),
            mevModuleData: ""
        });
        
        cfg.extensionConfigs = _buildExtensions(ethAmount);
        
        return IClanker(clanker).deployToken{value: ethAmount}(cfg);
    }
    
    function _buildLockerConfig(address creator) internal view returns (IClanker.LockerConfig memory) {
        address[] memory admins = new address[](1);
        admins[0] = creator;
        
        address[] memory recipients = new address[](1);
        recipients[0] = address(this);
        
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
            locker: address(0),
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
        
        exts[0] = IClanker.ExtensionConfig({
            extension: address(0),
            msgValue: ethAmount,
            extensionBps: 0,
            extensionData: abi.encode(
                address(0), address(0), uint24(0), int24(0), address(0),
                uint256(0),
                address(this)
            )
        });
        
        return exts;
    }
    
    function claim(uint256 launchId) external {
        Launch storage l = launches[launchId];
        if (l.status != Status.Launched) revert NotLaunched();
        acp.distribute(l.poolId, l.token);
    }
    
    function withdraw(uint256 launchId) external {
        Launch storage l = launches[launchId];
        if (l.status != Status.Funding || block.timestamp <= l.deadline) revert CannotWithdraw();
        l.status = Status.Expired;
        acp.distribute(l.poolId, address(0));
        
        emit Withdrawn(launchId);
    }
    
    function claimFees(uint256 launchId) external {
        Launch storage l = launches[launchId];
        if (l.status != Status.Launched) revert NotLaunched();
        if (l.token == address(0)) revert NoToken();
        
        IClankerFeeLocker(feeLocker).claim(address(this), l.token);
        
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        uint256 tokenBalance = IERC20(l.token).balanceOf(address(this));
        
        if (wethBalance > 0) {
            IERC20(weth).approve(address(acp), wethBalance);
            acp.depositToken(l.poolId, weth, wethBalance);
            acp.distribute(l.poolId, weth);
        }
        
        if (tokenBalance > 0) {
            IERC20(l.token).approve(address(acp), tokenBalance);
            acp.depositToken(l.poolId, l.token, tokenBalance);
            acp.distribute(l.poolId, l.token);
        }
        
        emit FeesClaimed(launchId, wethBalance, tokenBalance);
    }
    
    function availableFees(uint256 launchId) external view returns (uint256 wethFees, uint256 tokenFees) {
        Launch storage l = launches[launchId];
        if (l.status != Status.Launched || l.token == address(0)) return (0, 0);
        return IClankerFeeLocker(feeLocker).availableFees(address(this), l.token);
    }
    
    // ============ Views ============
    
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
