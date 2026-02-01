# Implementation Plan - Final

## Scope for Hackathon

### ✅ Definitely Shipping
1. **ACP** - Core pool primitive (done)
2. **Alpha** - Collective trading via Aerodrome

### ⚠️ Simplified Version
3. **Launchpad** - Simple token launch (not Clanker)

### ❌ Post-Hackathon
4. **NFTFlip** - Needs Seaport order construction
5. **Clanker Integration** - Too complex for 72h

---

## Verified Contract Addresses (Base Mainnet)

```solidity
// Core
address constant WETH = 0x4200000000000000000000000000000000000006;

// Aerodrome SlipStream (Uniswap V3 style)
address constant AERODROME_SWAP_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
address constant AERODROME_QUOTER = 0x254cF9E1E6e233aa1AC962CB9B05b2cfeaAe15b0;

// Aerodrome V2 (Velodrome style) 
address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

// Common tick spacings for SlipStream
int24 constant TICK_SPACING_STABLE = 1;    // 0.01%
int24 constant TICK_SPACING_LOW = 50;      // 0.5%
int24 constant TICK_SPACING_MEDIUM = 100;  // 1%
int24 constant TICK_SPACING_HIGH = 200;    // 2%
```

---

## Alpha Contract - Updated Design

Uses Aerodrome SlipStream for swaps.

```solidity
interface IAerodromeRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata) 
        external payable returns (uint256 amountOut);
}
```

**Trade creation includes tickSpacing** (not fee):
```solidity
function create(
    address tokenIn,
    address tokenOut,
    int24 tickSpacing,  // 1, 50, 100, or 200
    uint256 threshold,
    uint256 buyTime,
    uint256 sellTime,
    uint256 deadline
) external returns (uint256 tradeId);
```

---

## Launchpad - Simplified Design

**NOT using Clanker** - too complex. Instead:

1. Deploy standard ERC20 (OpenZeppelin)
2. Create Aerodrome V2 pool
3. Add liquidity
4. Distribute remaining tokens to contributors

```solidity
function launch(uint256 launchId) external {
    // 1. Deploy token
    ERC20 token = new SimpleToken(name, symbol, SUPPLY);
    
    // 2. Create pool via Aerodrome V2 factory
    address pool = IAerodromeFactory(FACTORY).createPool(
        address(token), 
        WETH, 
        false  // volatile pair
    );
    
    // 3. Add liquidity
    // (requires router.addLiquidity call)
    
    // 4. Send tokens to ACP for distribution
    token.transfer(address(acp), distributionAmount);
}
```

---

## Testing Strategy

### Base Sepolia (testnet)
- Deploy ACP
- Deploy Alpha with mock tokens
- Test full flow: create → join → buy → sell → claim

### Then Base Mainnet
- Deploy with real WETH
- Small amounts first

---

## Files to Update

1. `contracts/ACP.sol` - ✅ Good as is
2. `use-cases/alpha/Alpha.sol` - Update for Aerodrome tickSpacing
3. `use-cases/launchpad/Launchpad.sol` - Rewrite for simple token + Aerodrome V2

---

## Realistic Timeline

| Task | Time |
|------|------|
| Update Alpha for Aerodrome | 2h |
| Rewrite Launchpad (simple) | 3h |
| Deploy to testnet | 1h |
| Test + fix bugs | 2h |
| Deploy to mainnet | 1h |
| Frontend basics | 4h |
| **Total** | ~13h |

---

## Key Decisions

1. **Skip Clanker** - Their v4 interface is too complex (many required params, allowlisted hooks/lockers). Would need days to get right.

2. **Skip NFTFlip for now** - Seaport order construction is complex. Can add post-hackathon.

3. **Use Aerodrome V2 for Launchpad** - Simpler pool creation than SlipStream CL.

4. **Use Aerodrome SlipStream for Alpha** - Better price execution for trading.
