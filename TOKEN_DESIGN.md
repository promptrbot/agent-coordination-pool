# $COORD Token Design

## Philosophy

Agent Coordination Pool is about **contribution = vote**. No governance tokens, no democracy theater. The token should enhance coordination, not create overhead.

## Option 1: Simple Commemorative (RECOMMENDED)

**Complexity:** ⭐ (Minimal)  
**Value Add:** ⭐⭐ (Symbolic)

- ERC-20 with fixed supply
- No utility beyond representing project participation
- Can be distributed to early pool participants
- Acts as cultural artifact / community membership

**Implementation:** ~50 lines, just OpenZeppelin ERC20

```solidity
contract COORD is ERC20 {
    constructor() ERC20("Agent Coordination Token", "COORD") {
        _mint(msg.sender, 1_000_000 * 10**18); // 1M supply
    }
}
```

**Pros:**
- Ships in 5 minutes
- No ongoing maintenance
- Can't break the core protocol
- Community can add utility later organically

**Cons:**
- No immediate utility
- Might seem pointless

## Option 2: Credit System

**Complexity:** ⭐⭐⭐ (Moderate)  
**Value Add:** ⭐⭐⭐⭐ (High)

- Earn COORD for contributing to successful pools
- Burn COORD to create new pools (spam prevention)
- Reputation-weighted: bigger successful contributions = more COORD

**Implementation:** Requires modifying ACP to track outcomes, ~200 lines

**Pros:**
- Aligned with actual usage
- Natural spam prevention
- Rewards good actors

**Cons:**
- Requires protocol changes
- Need to define "successful" (time-based? profit-based?)
- More attack surface

## Option 3: Fee Capture

**Complexity:** ⭐⭐⭐⭐ (Complex)  
**Value Add:** ⭐⭐⭐⭐⭐ (Very High)

- Take 0.5% of all pool proceeds
- Distribute to COORD stakers
- Creates real yield without governance

**Implementation:** Modify distribute() in ACP, add staking contract, ~300 lines

**Pros:**
- Real yield = real value
- Aligns token holders with protocol success
- No governance needed

**Cons:**
- Protocol now extracts value (philosophical shift)
- Tax on coordination might reduce participation
- Staking contract adds complexity
- Need to think through fee mechanics carefully

## Option 4: Discount Token

**Complexity:** ⭐⭐⭐ (Moderate)  
**Value Add:** ⭐⭐⭐ (Medium)

- Hold/stake COORD → pay lower pool fees
- Burn COORD → create premium pools with features

**Implementation:** ~150 lines, new fee system + token gate

**Pros:**
- Simple value prop
- Encourages holding

**Cons:**
- Requires introducing fees (currently free)
- Creates two-tier system

## Recommendation: Start Simple

**Ship Option 1 now:**
1. Deploy basic ERC-20
2. Airdrop to early participants of ACP pools
3. Let community discover utility organically
4. Revisit utility in 3-6 months when usage patterns clear

**Why:**
- You don't have usage data yet to optimize for
- Complex tokenomics without usage = premature optimization
- Can always add utility later via wrapper contracts
- Token exists as coordination schelling point immediately

## Alternative: No Token Yet

Wait until:
- 10+ successful pools executed
- Clear pain points emerge that a token would solve
- Community asks for it

## If You Must Add Utility Now

**Minimal Credit System:**
```solidity
// Earn 1 COORD per 0.1 ETH contributed to executed pools
// Burn 10 COORD to create a pool
// Prevents spam, rewards participation
```

This is the smallest increment that adds real utility without overengineering.

---

**Decision Framework:**
- Want to ship something → Option 1
- Want real utility → Minimal Credit System
- Want to wait for data → No token yet
- Want maximum value → Option 3 (but wait 6 months)
