# ACP System Security Audit

## Executive Summary

Audited contracts:
- `ACP.sol` - Core coordination pool
- `AlphaTestable.sol` - Group trading wrapper
- `LaunchpadTestable.sol` - Token launch wrapper

**Overall Assessment:** ✅ All critical and high severity issues fixed.

---

## Fixed Issues

### ✅ FIX #1: Per-Pool Token Balance Tracking (was Critical)

**Problem:** ERC20 distribution used global `balanceOf` - first pool to distribute took everything.

**Solution:** Added `poolTokenBalances` mapping for per-pool tracking:
```solidity
mapping(uint256 => mapping(address => uint256)) public poolTokenBalances;
```

**Test:** `test_Security_PerPoolTokenTracking_Isolated()`

---

### ✅ FIX #2: Slippage Protection (was Critical)

**Problem:** Alpha swaps had `amountOutMinimum: 0` - MEV sandwich attacks.

**Solution:** Added configurable slippage:
```solidity
uint256 public constant MAX_SLIPPAGE_BPS = 1000; // 10% max
uint256 maxSlippageBps; // Per-trade setting
```

**Test:** `test_Security_Alpha_SlippageLimit()`, `test_Security_Alpha_CustomSlippage()`

---

### ✅ FIX #3: Max Contributors Limit (was Critical)

**Problem:** Unbounded contributor loop could exceed block gas limit.

**Solution:** Added contributor cap:
```solidity
uint256 public constant MAX_CONTRIBUTORS = 250;
```

**Test:** `test_Security_MaxContributors_Enforced()`, `test_Security_MaxContributors_DistributionSucceeds()`

---

### ✅ FIX #4: Reentrancy Guard (was High)

**Problem:** `distribute()` sent ETH in loop before completion.

**Solution:** Added OpenZeppelin's `ReentrancyGuard`:
```solidity
function distribute(...) external onlyController(poolId) nonReentrant
```

**Test:** `test_Security_ReentrancyGuard_BlocksAttack()`, `test_Security_ReentrancyGuard_CantDistributeTwice()`

---

### ✅ FIX #5: Fee-on-Transfer Token Handling (was High)

**Problem:** Recorded `amount` but received `amount - fee`.

**Solution:** Measure actual received:
```solidity
uint256 balBefore = IERC20(p.token).balanceOf(address(this));
IERC20(p.token).safeTransferFrom(msg.sender, address(this), amount);
uint256 received = IERC20(p.token).balanceOf(address(this)) - balBefore;
_recordContribution(poolId, contributor, received);
```

**Test:** `test_Security_FeeOnTransfer_CorrectAccounting()`, `test_Security_FeeOnTransfer_DistributionWorks()`

---

### ✅ FIX #6: Custom Errors (was Low)

**Problem:** Mix of `require()` strings and custom errors.

**Solution:** All errors now custom:
```solidity
error NotController();
error NotETHPool();
error ZeroValue();
error InsufficientBalance();
error TransferFailed();
error TooManyContributors();
error ExecutionFailed();
```

---

### ✅ FIX #7: Missing Events (was Low)

**Solution:** Added:
```solidity
event Deposited(uint256 indexed poolId, uint256 amount);
event TokenDeposited(uint256 indexed poolId, address token, uint256 amount);
```

---

### ✅ FIX #8: Pagination (was Low)

**Solution:** Added paginated view:
```solidity
function getContributorsPaginated(uint256 poolId, uint256 start, uint256 count) external view
```

**Test:** `test_Security_Pagination_GetContributors()`

---

### ✅ FIX #9: Unique Salt (was Medium)

**Problem:** Fixed salt prevented multiple tokens with same name/symbol.

**Solution:** Dynamic salt:
```solidity
bytes32 salt = keccak256(abi.encodePacked(address(this), launchId, block.timestamp));
```

---

## Not Fixed (By Design)

### Controller Transfer - Not Added

**Rationale:** User requested "keys are a user's problem" - trustless design.

### Emergency Withdrawal - Not Added

**Rationale:** Would break trustlessness. If external call reverts, that's the user's risk.

---

## Test Coverage

**215 tests passing:**
- `ACP.t.sol` - 65 tests
- `ACP.comprehensive.t.sol` - 29 tests
- `Alpha.t.sol` - 26 tests
- `Alpha.comprehensive.t.sol` - 28 tests
- `Launchpad.t.sol` - 19 tests
- `Launchpad.comprehensive.t.sol` - 26 tests
- `Security.t.sol` - 22 tests (dedicated security tests)

### Security Test Coverage

Each fix has dedicated tests in `Security.t.sol`:
- Reentrancy attack simulation
- Max contributors enforcement
- Per-pool token isolation
- Fee-on-transfer accounting
- Slippage protection
- Pagination correctness

---

## API Changes

### ACP.sol

```diff
+ mapping(uint256 => mapping(address => uint256)) public poolTokenBalances;
+ uint256 public constant MAX_CONTRIBUTORS = 250;

- function depositToken(uint256 poolId, uint256 amount)
+ function depositToken(uint256 poolId, address token, uint256 amount)

+ function getPoolTokenBalance(uint256 poolId, address token) external view
+ function getContributorsPaginated(uint256 poolId, uint256 start, uint256 count) external view
```

### AlphaTestable.sol

```diff
+ function create(..., uint256 maxSlippageBps) // New 7-param version
+ function setExpectedOutputs(uint256 tradeId, uint256 expectedBuy, uint256 expectedSell)
+ function getSlippageInfo(uint256 tradeId) external view
```

---

## Deployment Checklist

- [x] All critical issues fixed
- [x] All high severity issues fixed
- [x] Comprehensive test coverage
- [ ] Verify on Basescan after deployment
- [ ] Set appropriate slippage limits for production
- [ ] Monitor events for anomalies

---

*Audit conducted: 2026-02-02*
*All fixes implemented and tested*
*CI Status: ✅ Green*
