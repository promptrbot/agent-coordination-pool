// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title COORD - Agent Coordination Token
 * @notice Commemorative token for Agent Coordination Pool participants.
 * 
 * No governance. No fees. Just a schelling point for the community.
 * 
 * Utility can be added later via external contracts without modifying this token.
 * This is intentionally minimal to avoid premature optimization.
 */
contract COORD is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18; // 1M tokens
    
    /**
     * @notice Deploy COORD token with fixed supply
     * @param initialHolder Address to receive initial supply (for distribution)
     */
    constructor(address initialHolder) ERC20("Agent Coordination Token", "COORD") {
        require(initialHolder != address(0), "zero address");
        _mint(initialHolder, TOTAL_SUPPLY);
    }
}
