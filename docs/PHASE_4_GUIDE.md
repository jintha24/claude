# Phase 4 — The Market, Crowds and Pickpocketing

Walk north up the street: it now opens into a **Spitalfields-style market square**. It has 16
costermongers' stalls (fish on ice, fruit, vegetables, bread, flowers, cloth, crockery, hot
chestnuts) under striped awnings, and a ring of shops and pubs around it: the Ten Bells, a
poulterer, a tailor, a pawnbroker, a watchmaker. About 30 shoppers wander and browse, 16 traders
cry their wares, and **Constable Dunn** walks the square. This is Harry's pickpocketing ground
(Mission 2, *Crowded Pockets*, happens here).

---

## Part 1 — How to pick a pocket

1. **Choose a mark.** A gentleman in a top hat carries the most: a gold pocket watch, a
   pocket-book or a cigar case. A lady might have a brooch or a locket. A trader has the day's
   takings. A working man has a few pennies, and robbing him will cost you Legend later
   (Phase 9: *"Take from those who won't miss it"*).
2. **Approach from behind or the side, unseen.** The prompt **[E] Pick pocket — a gentleman**
   appears when you're close behind them. Nothing happens from the front.
3. **Press E.** Harry falls into step behind the mark (he follows if they walk) and his hand goes
   into the pocket. A timing bar appears:
   - A **marker** sweeps back and forth. Press **E** while it's inside the **green** sweet spot.
   - Rich marks need **two** careful moves ("Unhook the chain…", then "Lift it…"). Everyone else
     needs one.
   - The thin bar underneath is the mark's **suspicion**. It rises the whole time, so don't
     dawdle. You have about 3 seconds per move.
4. **What makes it easier or harder:**
   - A **crowd** around the mark widens the green zone and slows their suspicion. Jostling hides
     the touch.
   - A **walking** mark narrows the zone and speeds up the marker.
   - **Night** widens the zone (Phase 5 brings the day/night cycle).
   - **Skill** upgrades (Phase 9) widen it further.
5. **Success:** coins go straight into your purse (top-right shows *Purse: 17s 6d*), and
   valuables go into your bag to sell to a fence (Phase 9). Each person can only be robbed once.
   About one rich victim in three **notices later** ("My watch! I've been robbed!"). If you're
   still close and in view, you're the obvious suspect.
6. **Failure:** the mark spins round shouting *"Thief! Stop, thief!"*.
   - It counts as a crime, and any constable who sees you will chase.
   - The shout carries about 28 m and puts every constable on edge.
   - A working man or trader may grab hold of you for a moment first.
   - Bystanders stop and stare, and some back away.
   - Walking away mid-attempt (move away, jump or crouch) abandons it. If they'd already felt
     something, they turn round anyway.

**Crowd cover:** standing among two or more people makes Harry noticeably harder to pick out.
The light gem dims.

**Money is period-correct:** pounds, shillings and pence (£1 = 20s, 1s = 12d). In 1866 a labourer
earned about £1 a week, a loaf cost about 6d, and a good gold watch was worth about £10.

---

## Part 2 — The townsfolk

| Behaviour | What they do |
|---|---|
| Wander | Walk between points around the square |
| Browse | Stop at a stall and look over the goods |
| Tend stall | Traders stay behind their stall and cry their wares when you're near ("Fresh herrings! Three a penny!") |
| Gawk | Stop and stare at a commotion: a shout of "Thief!", breaking glass, a man going down |
| Flee | Back away from a scuffle right next to them |
| Shout | Robbed or nearly robbed: point and shout |

- **Crowd avoidance:** every townsperson and constable uses Godot's navigation avoidance, so
  nobody walks through anybody. The tests check that no two people come within 45 cm of each
  other.
- **Level of detail:** people within 35 m are fully animated. Those at 35–80 m animate at a third
  of the rate, and beyond 80 m their poses freeze. Beyond 150 m they fade out. Their stand-in
  bodies share a single material, so a crowd costs about 12 draw calls per person. Phase 10's
  performance pass adds MultiMesh impostors for very distant crowds.

---

## Part 3 — Editing the market (Inspector)

Select **MarketSquare** in `main.tscn`:
- **Shoppers:** how many people wander the square (default 30).
- **Layout Seed:** reshuffles the shopfronts and building heights.

Stall goods, the shop names and the constable's beat are listed at the top of
`scripts/world/market_square.gd`.

Any Marker3D in the group `browse_points` (with metadata `look_at`, a Vector3) becomes a place
where shoppers stop to browse. Use this to add browsing spots in shop doorways and elsewhere.

**Real character models** for townsfolk use the same hook as the constables (see Phase 3,
Part 5). Set **Body Model Path** on a Civilian. Clip names: `idle`, `walk`, `run`,
`look_around` (browsing), `alert` (shouting).

---

## Part 4 — Tests

`tests/test_market.gd` adds 24 checks:
- The square: 16 stalls and traders, 30+ shoppers, the constable.
- Shoppers really wander and browse, and crowd avoidance holds.
- Money formatting and loot tables.
- No prompt from the front, a prompt from behind, a successful lift, and no second lift.
- A gentleman takes two moves.
- A fumble brings a shout, a crime, a constable's chase and gawking bystanders.
- A crowd widens the sweet spot, and crowd cover counts.
- Distant townsfolk drop to low detail.

The suite now has **98 checks**, all passing.
