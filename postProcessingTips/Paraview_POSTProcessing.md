Things done manually in ParaView (better for visual/exploratory
checks, or anything OpenFOAM's function objects don't cover well).
---

## Part 2 — ParaView (manual, visual/exploratory)

### Flow rate through a patch (confirmed working, use if the OpenFOAM route ever breaks again)

1. Isolate the patch (`inlet` or `outlet_port`) in the reader's patch selection.
2. **Generate Surface Normals** filter.
3. **Calculator** filter: `dot(U,Normals)`, result name e.g. `Un`.
4. **Integrate Variables** filter on top — the integrated `Un` value IS the flow rate (m³/s).
5. Sign convention: `Normals` point outward from the fluid — expect **negative** at
   `inlet` (flow going in), **positive** at `outlet_port` (flow going out). Compare
   magnitudes, not raw signed values.

### Velocity field / rotation visualization

- Load `case.foam`, enable **Read Zones** in the reader properties (exposes `cellZone`
  `rotor` as a selectable region, separate from the boundary patches).
- **Glyph** filter for vector arrows: set **both Orientation Array and Scale Array to
  `U`**, not `Normals` — a `Slice` filter auto-adds a constant `Normals` array, and
  leaving Glyph's orientation on that default gives uniform, meaningless arrows (this
  bit us once already).
- **Plot Over Line**, axis to r=6mm, to see the radial velocity profile out from the
  shaft through the blade tip — useful for checking whether MRF is adding anything on
  top of `rotatingWallVelocity` (compare against the analytic 0.838 m/s at the tip).

### Shear rate near the blade

**Gradient** filter on `U` → strain-rate magnitude (or use the built-in Q-criterion/strain
rate option some ParaView versions expose directly in the Gradient filter dropdown).
Slice near the blade, color by this — expect it to peak right at the blade edges.

### Turbulent kinetic energy distribution

Load `k` directly, slice at several heights through and around the impeller, color by
`k`. Expect a clear hot spot at the blade tip, decaying with distance — the healthy
pattern. `k` staying near its small initial value far from the impeller may mean the
run hasn't developed far enough yet, not necessarily a real result.

### Dead zone detection

**Threshold** filter on `U` magnitude, low cutoff (e.g. <1% of blade tip speed,
~0.008 m/s). Whatever passes the threshold is a stagnant region — check tank corners,
behind the shaft, and behind baffles, the usual suspects in a stirred tank.

### Stepping through time

**View → Animation View**, step through saved timesteps, watching whether a quantity is
still visibly changing (still developing) or has settled into a repeating/steady
pattern (see the two-timescale note below).

---

## Reminder: two different timescales, don't conflate them

- **Local, impeller-driven** (fast — check within a few seconds of simulated time):
  blade-tip flow pattern should settle into a repeating, once-per-revolution pattern
  within a few tens of rotor revolutions (rotor period = 30ms).
- **Global, feed-driven tank turnover** (slow — full residence time ≈653s): the bulk
  circulation pattern will still be visibly developing for a very long time by
  comparison. Don't expect the whole tank to look "settled" just because the
  impeller region has stopped changing.
