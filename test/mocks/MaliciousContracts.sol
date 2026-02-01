// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IACP {
    function contribute(uint256 poolId, address contributor) external payable;
    function distribute(uint256 poolId, address token) external;
}

/// @notice Contract that attempts reentrancy attacks
contract MaliciousReceiver {
    IACP public acp;
    uint256 public targetPool;
    bool public attemptReentrancy;
    uint256 public reentrancyCount;
    
    constructor(address _acp) {
        acp = IACP(_acp);
    }
    
    function setReentrancyTarget(uint256 _pool) external {
        targetPool = _pool;
        attemptReentrancy = true;
    }
    
    receive() external payable {
        if (attemptReentrancy && reentrancyCount < 3) {
            reentrancyCount++;
            // Try to reenter - should fail due to access control
            try acp.distribute(targetPool, address(0)) {} catch {}
        }
    }
    
    function reset() external {
        attemptReentrancy = false;
        reentrancyCount = 0;
    }
}

/// @notice Token that reverts on transfer
contract RevertingToken is ERC20 {
    bool public shouldRevert;
    
    constructor() ERC20("Reverting", "REV") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setShouldRevert(bool _should) external {
        shouldRevert = _should;
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldRevert) revert("Reverting!");
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldRevert) revert("Reverting!");
        return super.transferFrom(from, to, amount);
    }
}

/// @notice Token that takes a fee on transfer
contract FeeOnTransferToken is ERC20 {
    uint256 public feePercent = 5; // 5% fee
    address public feeCollector;
    
    constructor() ERC20("FeeToken", "FEE") {
        feeCollector = msg.sender;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setFeePercent(uint256 _fee) external {
        feePercent = _fee;
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 100;
        if (fee > 0) {
            super.transfer(feeCollector, fee);
        }
        return super.transfer(to, amount - fee);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 100;
        if (fee > 0) {
            _transfer(from, feeCollector, fee);
        }
        
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount - fee);
        return true;
    }
}

/// @notice Contract that consumes excessive gas
contract GasGriefingReceiver {
    uint256[] public data;
    bool public shouldGrief;
    
    function setGrief(bool _should) external {
        shouldGrief = _should;
    }
    
    receive() external payable {
        if (shouldGrief) {
            // Consume lots of gas
            for (uint i = 0; i < 1000; i++) {
                data.push(i);
            }
        }
    }
}

/// @notice Token that returns false instead of reverting
contract FalseReturningToken is ERC20 {
    bool public shouldReturnFalse;
    
    constructor() ERC20("FalseToken", "FALSE") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setShouldReturnFalse(bool _should) external {
        shouldReturnFalse = _should;
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldReturnFalse) return false;
        return super.transfer(to, amount);
    }
}
