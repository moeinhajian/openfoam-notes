# Simulation Scenario — Full Reference

## 1. What's actually driving the flow, and does it change over time?

| driver | value | changes over time? |
|---|---|---|
| Inlet volumetric flow rate | 1.217×10⁻⁸ m³/s (constant) | **No** — prescribed as `constant`, fixed for the whole run |
| Outlet flow rate | *not independently set* | Determined by the solver, not prescribed |
| Impeller rotation rate | 2000 rpm / ω=−209.44 rad/s (constant) | **No** — imposed as a step change at t=0, not ramped |

**Important nuance on the outlet**: `outlet_port` uses `fixedValue` pressure + `inletOutlet` velocity — this is a *passive* boundary, not a second prescribed flow rate. For incompressible flow, continuity requires the net volumetric flux through the *entire* closed boundary to be zero at every instant (no storage term, since density is constant) — so the outlet's actual flow rate isn't an input at all, it's an **output**, and it should track the inlet's 1.217×10⁻⁸ m³/s almost immediately (up to solver residual tolerance), not just "eventually." **This is itself a useful sanity check**: if you integrate `phi` over `outlet_port` and it doesn't match the inlet rate, that's a sign of a continuity/convergence problem, not a legitimate physical transient.

**Impeller start-up caveat worth knowing**: imposing a constant 2000 rpm from the very first timestep is an *impulsive start* — real motors ramp up over some seconds. This is a common simplifying assumption in CFD (avoids modeling motor torque curves), but it means the very early transient (first few rotor revolutions) reflects a somewhat artificial "instant spin-up," not a real startup sequence. Worth remembering if the very earliest timesteps look unusually aggressive.

## 2. Governing equations

Same as laid out earlier in this conversation — continuity, RANS momentum, k–ε closure:

- ∇·**u** = 0
- ∂**u**/∂t + ∇·(**u**⊗**u**) = −∇p + ∇·[(ν+ν_t)(∇**u**+∇**u**ᵀ)] + **g**
- k, ε transport equations, ν_t = C_μk²/ε

**Open question flagged, not yet resolved**: whether `MRF` (cellZone `rotor`) is *also* adding a redundant rotational correction on top of the already-physical `rotatingWallVelocity` BC on `impeller`. This could mean the blade's effective rotation is being double-counted in the currently-running case. Needs to be checked against this run's results (see §5) before trusting quantitative values near the impeller.

## 3. Key assumptions

- Incompressible, constant-density water, Newtonian, single-phase liquid (no free surface — domain is fully liquid-filled).
- RANS turbulence (k–ε): models the *statistical effect* of turbulence on the mean flow, does not resolve instantaneous turbulent eddies directly.
- Stationary mesh throughout — rotation represented via `rotatingWallVelocity` (and possibly MRF, pending §5), **not** real mesh motion or a sliding cyclicAMI interface.
- Placeholder impeller geometry — a plain cylindrical shaft + 2 flat crossbar blades, not a real blade profile. Fine for validating mixing *mechanics*, not for matching a specific real impeller's performance numbers.
- Gravity (`constant/g`) is present but **inert** — plain `pimpleFoam` never reads it into the momentum equation (that's only a buoyant-solver feature), so no buoyancy/stratification effects are modeled here.
- Mesh has ~4.3% concave cut-cells (flagged early on, accepted for this first-pass smoke test) — a possible, not confirmed, source of local numerical inaccuracy if results look physically odd near sharp features.

## 4. Boundary and initial conditions

| patch | U | p | k | ε | ν_t |
|---|---|---|---|---|---|
| `wall`, `wall_rotor`, `domeWall` | `noSlip` | `zeroGradient` | `kqRWallFunction` | `epsilonWallFunction` | `nutkWallFunction` |
| `impeller` | `rotatingWallVelocity` (ω=−209.44 rad/s) | `zeroGradient` | `kqRWallFunction` | `epsilonWallFunction` | `nutkWallFunction` |
| `inlet` | `flowRateInletVelocity` | `zeroGradient` | `turbulentIntensityKineticEnergyInlet` (5%) | `turbulentMixingLengthDissipationRateInlet` | `calculated` |
| `outlet_port` | `inletOutlet` | `fixedValue 0` | `inletOutlet` | `inletOutlet` | `calculated` |

Initial conditions: **U=0, p=0** everywhere (fluid starts completely at rest — this was the original project goal, watching development from dead rest); **k=0.0171 m²/s², ε=0.258 m²/s³** (derived from rotor tip speed, not arbitrary).

## 5. What to actually track, and how to judge "has it reached equilibrium"

There isn't one single equilibrium here — there are **two very different timescales**, and conflating them will give a misleading picture:

- **Local, impeller-driven quasi-equilibrium** (fast): the flow pattern *right around the blade* — tip vortices, local shear layers — should settle into a repeating (periodic, once-per-revolution) pattern within a few tens of rotor revolutions (rotor period = 30ms, so within roughly 1–2 seconds).
- **Global, feed-driven tank turnover** (slow): full-domain residence time is ~653s. The bulk macro-circulation pattern — how far the impeller's influence actually reaches, how the inlet jet integrates with it — will still be visibly developing at t=2s, and won't be "done" for a very long time by comparison.

Track them separately. Don't expect the whole tank to look "settled" just because the region right at the blade tip has stopped changing.

### Concrete things worth calculating

- **Continuity/mass balance check** (do this first, cheapest, most diagnostic): integrate `phi` over `inlet` and over `outlet_port` each timestep — they should match closely. A persistent mismatch means a convergence problem, not a real transient.
- **Impeller torque / power draw** — add a `forces`/`forceCoeffs`-style function object on the `impeller` patch. This is the classic mixing-tank metric (relates to the dimensionless Power Number, Np) and directly tells you how hard the impeller is actually working on the fluid.
- **Shear rate near the blade** — velocity gradient magnitude close to `impeller`. Matters if you ever care about shear-sensitive mixing (e.g. biological material) or just want to characterize local mixing intensity.
- **Turbulent kinetic energy (k) distribution** — where is turbulence actually being generated? High k near the blade tip, decaying with distance, is the expected healthy pattern; k staying near its initial small value far from the impeller may indicate poor momentum transport (or too short a run) rather than a real physical result.
- **Velocity field / streamlines for dead zones** — a real mixing-tank quality concern: regions of near-stagnant fluid (especially tank corners, behind baffles, near the free-standing shaft) indicate poor mixing coverage, independent of how well the impeller region itself is behaving.
- **Reynolds numbers, already computed, worth re-anchoring to**: rotor tip Re≈43,600 (turbulent — kEpsilon appropriate there), inlet Re≈6.6 (essentially laminar — kEpsilon will correctly predict near-zero eddy viscosity there, nothing wrong with that).
- **Residence Time Distribution (RTD)** — not set up yet, but a natural next extension: inject a passive scalar/tracer at the inlet and track its concentration history at the outlet. This is the standard way to quantify actual mixing performance (how long fluid parcels spend in the tank, how well they're mixed before leaving) — worth considering once the base flow is validated.

### The MRF double-counting question (resolve before trusting quantitative numbers)

Compare this run's blade-adjacent velocity magnitude against the simple analytic expectation `u = Ω×r` at the blade tip (r=4mm): `|u| = 209.44 × 0.004 ≈ 0.838 m/s`. If the simulation shows blade-tip velocities meaningfully *higher* than that (not just numerically close, but a clear multiple), that's evidence MRF is adding a redundant correction on top of `rotatingWallVelocity`. If it matches closely, the two mechanisms are coexisting harmlessly (or one is effectively dominating cleanly). This is a concrete, checkable number — worth pulling directly from the current run's results.
