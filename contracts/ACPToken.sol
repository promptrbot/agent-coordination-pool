// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ACPToken
 * @notice Commemorative token for Agent Coordination Pool participants
 * @dev Simple ERC-20 with fixed supply, no complex mechanics
 */
contract ACPToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18; // 1M tokens

    constructor() ERC20("Agent Coordination Pool", "ACP") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
