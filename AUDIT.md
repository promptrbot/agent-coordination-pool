# ACP System Security Audit

## Executive Summary

Audited contracts:
- `ACP.sol` - Core coordination pool
- `AlphaTestable.sol` - Group trading wrapper
- `LaunchpadTestable.sol` - Token launch wrapper

**Overall Assessment:** Medium risk. Several issues to address before mainnet.

---

## Critical Issues

### 1. ⚠️ ERC20 Distribution Uses Global Balance (ACP.sol:147-149)

```solidity
} else {
    // For ERC-20, use actual balance (received tokens go here)
    balance = IERC20(token).balanceOf(address(this));
}
```

**Problem:** When distributing ERC20 tokens, the contract uses `balanceOf(address(this))` which is the TOTAL balance across ALL pools. If multiple pools receive the same token, the first pool to distribute gets everything.

**Impact:** High - contributors to other pools lose their tokens

**Recommendation:**
```solidity
// Option A: Track per-pool token balances
mapping(uint256 => mapping(address => uint256)) public poolTokenBalances;

// Option B: Document as known limitation and prevent same-token pools
```

### 2. ⚠️ No Slippage Protection (Alpha.sol:108, 138)

```solidity
amountOutMinimum: 0,
```

**Problem:** Both buy and sell swaps have zero slippage protection. MEV bots can sandwich these transactions.

**Impact:** High - contributors can lose significant value to sandwich attacks

**Recommendation:**
```solidity
// Add slippage parameter to create()
uint256 public maxSlippageBps = 100; // 1% default

amountOutMinimum: (expectedAmount * (10000 - maxSlippageBps)) / 10000,
```

### 3. ⚠️ Unbounded Loop in distribute() (ACP.sol:158-172)

```solidity
for (uint256 i = 0; i < p.contributors.length; i++) {
```

**Problem:** No limit on contributors array. With 500+ contributors, distribution could exceed block gas limit.

**Impact:** Medium - pool becomes undistributable

**Recommendation:**
```solidity
// Add max contributors limit
uint256 public constant MAX_CONTRIBUTORS = 250;

// Or implement batch distribution
function distributeBatch(uint256 poolId, address token, uint256 startIndex, uint256 count) external
```

---

## High Severity

### 4. Missing Reentrancy Guard on distribute() (ACP.sol:145)

```solidity
(bool ok,) = c.call{value: share}("");
```

**Problem:** ETH transfer to contributor before loop completes. Malicious contract can reenter.

**Current Mitigation:** Balance is zeroed before loop (`p.balance = 0`), limiting reentrancy damage.

**Recommendation:** Add explicit `nonReentrant` modifier from OpenZeppelin for defense in depth.

### 5. Fee-on-Transfer Token Accounting Mismatch (ACP.sol:79-81)

```solidity
IERC20(p.token).safeTransferFrom(msg.sender, address(this), amount);
_recordContribution(poolId, contributor, amount);
```

**Problem:** Records `amount` but receives `amount - fee`. Distribution will fail when pool has less than recorded.

**Recommendation:**
```solidity
uint256 balBefore = IERC20(p.token).balanceOf(address(this));
IERC20(p.token).safeTransferFrom(msg.sender, address(this), amount);
uint256 received = IERC20(p.token).balanceOf(address(this)) - balBefore;
_recordContribution(poolId, contributor, received);
```

### 6. No Emergency Withdrawal (All Contracts)

**Problem:** No way for controller to recover funds if contract logic becomes stuck (e.g., external call always reverts).

**Recommendation:** Add emergency functions with timelock:
```solidity
function emergencyWithdraw(uint256 poolId, address to) external onlyController(poolId) {
    require(block.timestamp > emergencyUnlockTime[poolId], "locked");
    // transfer all funds to `to`
}
```

---

## Medium Severity

### 7. No Controller Transfer (ACP.sol)

**Problem:** Controller is set at pool creation and cannot be changed. If controller key is compromised or lost, pool is stuck.

**Recommendation:**
```solidity
function transferController(uint256 poolId, address newController) external onlyController(poolId) {
    pools[poolId].controller = newController;
    emit ControllerTransferred(poolId, msg.sender, newController);
}
```

### 8. execute() Allows Arbitrary Calls (ACP.sol:100)

**Problem:** Controller can make any call including to malicious contracts, token approvals, etc.

**Mitigation:** This is by design (controller is trusted), but document clearly.

**Recommendation:** Consider adding optional call restrictions or allowlists for high-security deployments.

### 9. Timestamp Dependence (Alpha.sol:92, 134)

```solidity
require(block.timestamp >= t.buyTime, "too early");
```

**Problem:** Miners can manipulate `block.timestamp` by ~15 seconds.

**Impact:** Low - minor timing manipulation possible

**Recommendation:** Acceptable for non-critical timing. Document limitation.

### 10. Salt Collision (Launchpad.sol:163)

```solidity
salt: bytes32(0),
```

**Problem:** Fixed salt means only one token per name/symbol combo can be deployed via this contract.

**Recommendation:**
```solidity
salt: keccak256(abi.encodePacked(launchId, block.timestamp))
```

---

## Low Severity

### 11. Missing Events for State Changes

- `deposit()` and `depositToken()` have no events
- `withdraw()` in Alpha/Launchpad has no event

**Recommendation:** Add events for off-chain tracking.

### 12. No Input Validation on Addresses

```solidity
function contribute(uint256 poolId, address contributor) // contributor could be address(0)
```

**Problem:** Can contribute to `address(0)`. While this works, it may confuse off-chain systems.

**Recommendation:** Add `require(contributor != address(0), "zero address")` or document as acceptable.

### 13. Inconsistent Error Handling

Some functions use `require()` strings, others use custom errors:
- `require(msg.value > 0, "no value");` 
- `revert NotController();`

**Recommendation:** Convert all to custom errors for gas savings and consistency.

### 14. View Function Gas (getContributors)

```solidity
function getContributors(uint256 poolId) external view returns (address[] memory) {
    return pools[poolId].contributors;
}
```

**Problem:** Returns unbounded array. Will fail for large pools.

**Recommendation:** Add pagination:
```solidity
function getContributorsPaginated(uint256 poolId, uint256 start, uint256 count) external view
```

---

## Gas Optimizations

### 15. Storage Reads in Loop

```solidity
for (uint256 i = 0; i < p.contributors.length; i++) {
    address c = p.contributors[i];
    uint256 share = (balance * p.contributions[c]) / p.totalContributed;
```

**Recommendation:** Cache `p.totalContributed` and `p.contributors.length` before loop:
```solidity
uint256 total = p.totalContributed;
uint256 len = p.contributors.length;
for (uint256 i = 0; i < len; i++) {
```

### 16. Struct Packing (Alpha.sol)

```solidity
struct Trade {
    uint256 poolId;        // slot 0
    address tokenOut;      // slot 1 (only 20 bytes)
    uint256 threshold;     // slot 2
    // ...
}
```

**Recommendation:** Pack smaller types together:
```solidity
struct Trade {
    uint256 poolId;
    uint256 threshold;
    uint256 buyTime;
    uint256 sellTime;
    uint256 deadline;
    uint256 tokensHeld;
    address tokenOut;      // 20 bytes
    int24 tickSpacing;     // 3 bytes
    Status status;         // 1 byte
    // All fit in 7 slots instead of 9
}
```

---

## Recommendations Summary

### Must Fix Before Mainnet:
1. Add slippage protection to Alpha swaps
2. Implement max contributor limit OR batch distribution
3. Document ERC20 multi-pool limitation clearly
4. Add reentrancy guard to distribute()

### Should Fix:
5. Handle fee-on-transfer tokens correctly
6. Add controller transfer function
7. Add emergency withdrawal with timelock
8. Convert all errors to custom errors

### Nice to Have:
9. Add missing events
10. Add pagination to view functions
11. Gas optimizations (struct packing, loop caching)
12. Input validation on addresses

---

## Test Coverage Gaps

Current: 201 tests ✓

**Missing test scenarios:**
- [ ] Reentrancy attack on distribute() (have test but no actual attack)
- [ ] Gas limit test with 500+ contributors
- [ ] Multi-pool same-token distribution conflict
- [ ] Sandwich attack simulation on Alpha swaps
- [ ] Fee-on-transfer token with actual fee deduction

---

## Deployment Checklist

- [ ] Verify all external contract addresses (Clanker, Router, WETH, FeeLocker)
- [ ] Set appropriate slippage limits
- [ ] Set max contributor limits
- [ ] Deploy with timelock admin if needed
- [ ] Verify on Basescan
- [ ] Set up monitoring for events

---

*Audit conducted: 2026-02-02*
*Contracts version: Latest commit*
