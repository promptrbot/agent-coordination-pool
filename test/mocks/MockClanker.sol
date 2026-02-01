// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Simple token for Clanker mock deployments
contract MockClankerToken is ERC20 {
    constructor(string memory name, string memory symbol, address recipient, uint256 amount) 
        ERC20(name, symbol) 
    {
        _mint(recipient, amount);
    }
}

/// @notice Mock Clanker v4 Factory for testing
contract MockClanker {
    // Track deployments
    struct Deployment {
        address token;
        string name;
        string symbol;
        uint256 ethReceived;
        address creator;
    }
    Deployment[] public deployments;
    
    // Token supply constant (matches real Clanker)
    uint256 public constant TOKEN_SUPPLY = 100_000_000_000e18; // 100B
    
    // Configurable: what % of ETH gets converted to tokens via devBuy
    // In basis points, 10000 = 100%
    uint256 public devBuyEfficiencyBps = 10000;
    
    // DevBuy recipient tracking
    address public lastDevBuyRecipient;
    
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
    
    event TokenDeployed(address token, string name, string symbol, uint256 ethReceived);
    
    constructor() {}
    
    /// @notice Set devBuy efficiency (for testing different scenarios)
    function setDevBuyEfficiency(uint256 bps) external {
        devBuyEfficiencyBps = bps;
    }
    
    /// @notice Deploy a token (mock implementation)
    function deployToken(DeploymentConfig calldata config) external payable returns (address) {
        // Find devBuy extension and recipient
        address devBuyRecipient = msg.sender;
        uint256 devBuyValue = 0;
        
        for (uint i = 0; i < config.extensionConfigs.length; i++) {
            if (config.extensionConfigs[i].msgValue > 0) {
                devBuyValue = config.extensionConfigs[i].msgValue;
                // Decode recipient from extensionData (last address in the encoded data)
                bytes memory data = config.extensionConfigs[i].extensionData;
                if (data.length >= 32) {
                    // Recipient is last 20 bytes
                    assembly {
                        devBuyRecipient := mload(add(data, mload(data)))
                    }
                }
                break;
            }
        }
        
        lastDevBuyRecipient = devBuyRecipient;
        
        // Deploy new token
        MockClankerToken token = new MockClankerToken(
            config.tokenConfig.name,
            config.tokenConfig.symbol,
            address(this),
            TOKEN_SUPPLY
        );
        
        // Simulate devBuy: convert ETH to tokens for recipient
        // In real Clanker, this would be a swap. We simulate with a ratio.
        if (devBuyValue > 0 && devBuyRecipient != address(0)) {
            // Calculate tokens to send based on ETH value
            // Simplified: 1 ETH = 1B tokens (1% of supply)
            uint256 tokensPerEth = TOKEN_SUPPLY / 100;
            uint256 tokensOut = (devBuyValue * tokensPerEth * devBuyEfficiencyBps) / (1 ether * 10000);
            
            // Cap at available supply
            uint256 available = token.balanceOf(address(this));
            if (tokensOut > available) tokensOut = available;
            
            // Transfer to devBuy recipient
            token.transfer(devBuyRecipient, tokensOut);
        }
        
        // Record deployment
        deployments.push(Deployment({
            token: address(token),
            name: config.tokenConfig.name,
            symbol: config.tokenConfig.symbol,
            ethReceived: msg.value,
            creator: msg.sender
        }));
        
        emit TokenDeployed(address(token), config.tokenConfig.name, config.tokenConfig.symbol, msg.value);
        
        return address(token);
    }
    
    /// @notice Get deployment count
    function deploymentCount() external view returns (uint256) {
        return deployments.length;
    }
    
    /// @notice Get last deployed token
    function lastDeployedToken() external view returns (address) {
        if (deployments.length == 0) return address(0);
        return deployments[deployments.length - 1].token;
    }
}

/// @notice Mock Clanker Fee Locker for testing fee claiming
contract MockClankerFeeLocker {
    // Accumulated fees per recipient per token
    // recipient => token => (wethFees, tokenFees)
    mapping(address => mapping(address => uint256)) public wethFees;
    mapping(address => mapping(address => uint256)) public tokenFees;
    
    address public weth;
    
    constructor(address _weth) {
        weth = _weth;
    }
    
    /// @notice Add fees for testing
    function addFees(address recipient, address token, uint256 _wethFees, uint256 _tokenFees) external {
        wethFees[recipient][token] += _wethFees;
        tokenFees[recipient][token] += _tokenFees;
    }
    
    /// @notice Get available fees
    function availableFees(address recipient, address token) external view returns (uint256, uint256) {
        return (wethFees[recipient][token], tokenFees[recipient][token]);
    }
    
    /// @notice Claim fees
    function claim(address recipient, address token) external {
        uint256 wethAmount = wethFees[recipient][token];
        uint256 tokenAmount = tokenFees[recipient][token];
        
        wethFees[recipient][token] = 0;
        tokenFees[recipient][token] = 0;
        
        if (wethAmount > 0) {
            IERC20(weth).transfer(msg.sender, wethAmount);
        }
        if (tokenAmount > 0) {
            IERC20(token).transfer(msg.sender, tokenAmount);
        }
    }
    
    /// @notice Fund the mock with tokens
    function fund(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}
