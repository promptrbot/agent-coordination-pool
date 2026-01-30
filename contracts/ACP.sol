// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ACP - Agent Coordination Pool
 * @notice Pool ETH. Execute a call. That's it.
 * 
 * FOR AGENTS:
 *   1. Find a pool you want to join
 *   2. contribute(poolId) with ETH
 *   3. When funded: execute(poolId)
 *   4. If expired: withdraw(poolId)
 * 
 * 87 lines. Fully auditable.
 */
contract ACP {
    
    struct Pool {
        address target;           // Contract to call
        bytes callData;           // What to call
        uint256 value;            // ETH to send
        uint256 threshold;        // Min ETH needed
        uint256 deadline;         // When it expires
        uint256 total;            // Total contributed
        bool executed;            // Already executed?
        mapping(address => uint256) contributions;
    }
    
    Pool[] public pools;
    
    event Created(uint256 indexed id, address target, uint256 threshold, uint256 deadline);
    event Contributed(uint256 indexed id, address indexed who, uint256 amount);
    event Executed(uint256 indexed id, bool success);
    event Withdrawn(uint256 indexed id, address indexed who, uint256 amount);
    
    /// @notice Create a pool
    function create(
        address target,
        bytes calldata callData,
        uint256 value,
        uint256 threshold,
        uint256 deadline
    ) external returns (uint256 id) {
        require(threshold > 0, "threshold=0");
        require(deadline > block.timestamp, "deadline passed");
        
        id = pools.length;
        Pool storage p = pools.push();
        p.target = target;
        p.callData = callData;
        p.value = value;
        p.threshold = threshold;
        p.deadline = deadline;
        
        emit Created(id, target, threshold, deadline);
    }
    
    /// @notice Add ETH to a pool
    function contribute(uint256 id) external payable {
        Pool storage p = pools[id];
        require(!p.executed, "already executed");
        require(block.timestamp <= p.deadline, "expired");
        require(msg.value > 0, "no value");
        
        p.contributions[msg.sender] += msg.value;
        p.total += msg.value;
        
        emit Contributed(id, msg.sender, msg.value);
    }
    
    /// @notice Execute the call (when funded)
    function execute(uint256 id) external returns (bool success) {
        Pool storage p = pools[id];
        require(!p.executed, "already executed");
        require(p.total >= p.threshold, "not funded");
        require(block.timestamp <= p.deadline, "expired");
        
        p.executed = true;
        (success,) = p.target.call{value: p.value}(p.callData);
        
        emit Executed(id, success);
    }
    
    /// @notice Get your ETH back (if expired or failed)
    function withdraw(uint256 id) external {
        Pool storage p = pools[id];
        require(
            block.timestamp > p.deadline || (p.executed && p.total < p.threshold),
            "cannot withdraw"
        );
        
        uint256 amount = p.contributions[msg.sender];
        require(amount > 0, "nothing to withdraw");
        
        p.contributions[msg.sender] = 0;
        p.total -= amount;
        
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        
        emit Withdrawn(id, msg.sender, amount);
    }
    
    /// @notice How much did someone contribute?
    function contribution(uint256 id, address who) external view returns (uint256) {
        return pools[id].contributions[who];
    }
    
    /// @notice How many pools exist?
    function count() external view returns (uint256) {
        return pools.length;
    }
    
    receive() external payable { revert("use contribute()"); }
}
