# OpenFOAM Stirred-Tank CFD — Project Knowledge Summary

Carried forward from a full build: geometry → mesh → single-phase (transient, then
steady) → two-phase solid-liquid, on OpenFOAM 5. Written to be useful as
context for a *new* project on different geometry, including a planned
two-inlet, both-liquid multiphase case.

## 1. Overall architecture that worked

Two separate OpenFOAM case directories, not one:
- **`mesh/`** — geometry in, mesh out. Only ever runs meshing utilities
  (`blockMesh`, `snappyHexMesh`, `checkMesh`, `topoSet`, `createPatch`,
  `setsToZones`). Needs its own **minimal** `system/fvSchemes` +
  `system/fvSolution` (just enough to satisfy `snappyHexMesh`'s internal
  point-displacement smoothing solve) — this is easy to forget and causes a
  confusing failure if omitted, since it looks unrelated to physics.
- **`case/`** (or several variants — `case/`, `case_twophase/`, etc.) — the
  actual solved problem. `constant/polyMesh` gets copied in from `mesh/`
  after meshing is complete; never regenerate the mesh from inside the
  solver case.

**Geometry strategy**: a single watertight STL representing the *fluid
volume itself* (not the tank's solid material) worked well — verify
watertightness computationally (every directed edge should have exactly one
reverse-paired partner, zero open boundary edges) before trusting it.
Multiple named regions in one STL (`solid <name> ... endsolid <name>`
blocks) map cleanly to multiple patches via `snappyHexMeshDict`'s
`regions {}` sub-dict under one `triSurfaceMesh` geometry entry.

## 2. Meshing — concrete lessons

- **`locationInMesh` must be verified, not guessed.** Ray-cast the candidate
  point against the actual STL (count edge crossings along several
  directions — odd = inside) rather than trusting a CAD-derived coordinate.
  Axis conventions between CAD and OpenFOAM can silently swap (we found a
  CAD-Y ↔ OpenFOAM-Z mapping this way).
- **Any new internal obstacle geometry (e.g. an impeller/shaft) moves
  `locationInMesh` off wherever it used to be** — check it isn't now sitting
  inside the new solid.
- **Refinement is expensive; be surgical.** Blanket high refinement across
  an entire patch (rather than a local `refinementRegion` around just the
  feature that needs it, e.g. a thin clearance gap) inflates cell count fast
  and can itself cause mesh-quality problems (we saw ~4.3% concave cut-cells
  from aggressive refinement against curved features).
- **`cylinderToFace` does not exist** in OF5 `topoSet`. For a cylindrical
  face selection, use `cylinderToCell` (cell-centroid based) → `cellToFace`
  (option `all`) as a two-step substitute, or `boxToFace` (face-centre
  based) as a squared-off approximation if cell-centroid selection misses
  faces near concave/irregular cut-cells.
- **`setsToZones` has no `-dict` override** — it always reads
  `system/setsToZonesDict` by filename convention, AND it indiscriminately
  tries to convert *every* set sitting in `constant/polyMesh/sets/`,
  including stray diagnostic sets `checkMesh` writes (`concaveCells`,
  `warpedFaces`, etc.). Clear that directory of anything not meant to
  become a permanent zone before running it.
- **`createPatch` is one-shot and destructive.** Once run, the original
  source patch is consumed/restructured — you cannot retry against the same
  mesh state if the result is wrong. Always regenerate from `snappyHexMesh`
  onward before attempting a patch split again.
- **Splitting a patch into two: build both faceSets explicitly via
  `topoSet` (including the complement, using `action delete`), then have
  `createPatch` build *both* new patches via `constructFrom set`.** Letting
  one patch be `constructFrom set` and the other `constructFrom patches`
  ("whatever's left") is ambiguous — one silently claimed everything and
  the other got zero faces in our case.
- **Geometric patch *type* (`wall` vs `patch` in `snappyHexMeshDict`'s
  `patchInfo`) is separate from the field boundary condition *type*** (e.g.
  `noSlip` in `0/U`). Turbulence wall functions (`nutkWallFunction` etc.)
  require the geometric type to be `wall` specifically — a patch can have a
  perfectly valid `noSlip` field BC and still fail if its geometric type is
  `patch`.

## 3. Single-phase liquid — transient vs steady

- **Transient (`pimpleFoam`)**: real physical time, `ddtSchemes { default
  Euler; }`. Watch real spin-up develop. Needs `UFinal`/`kFinal`/
  `epsilonFinal` solver entries in `fvSolution` whenever `nOuterCorrectors
  1` — with only one outer corrector, *every* solve is trivially the
  "final" one, so PIMPLE always requests the `Final`-suffixed name, never
  the plain one.
- **Steady (`simpleFoam`)**: `ddtSchemes { default steadyState; }` — this
  deletes the ∂u/∂t term from the momentum equation entirely. "Iterations"
  are not physical time; intermediate iterations are not meaningful
  physical states, only the converged (residual-below-threshold) result is.
  Needs `relaxationFactors` (SIMPLE-specific, no `Final` variants needed at
  all — simpler than PIMPLE in that respect). `residualControl` entries
  must each be a sub-dictionary (`{ tolerance ...; relTol ...; }`), not a
  bare number.
- **MRF (frozen rotor)**: standard/textbook usage is plain `noSlip` on the
  rotating patch — MRF's own boundary-velocity correction supplies the
  Ω×r rotation for cells inside the `cellZone`. Using `rotatingWallVelocity`
  instead works too (it computes the same physical velocity directly,
  independent of MRF), but risks double-counting if combined with MRF on
  the same patch — pick one mechanism, don't stack both without a specific
  reason.
- **A patch outside the MRF cellZone but part of a continuously-rotating
  solid (e.g. an extended shaft) needs `rotatingWallVelocity` specifically,
  since MRF's correction never reaches it.** Plain `noSlip` there
  incorrectly renders it stationary. We accepted this as a known
  simplification when the effect was small (thin shaft, far from the main
  momentum source); worth revisiting properly (split into an
  in-zone/out-of-zone patch pair) if it turns out to matter.
- **A fully closed domain (all patches `zeroGradient` on p) is a singular
  pressure system** — needs `pRefCell`/`pRefValue` in `fvSolution`. Once any
  patch gets a `fixedValue` pressure (e.g. a real outlet), this becomes
  automatically inactive — safe to leave in either way.
- **MRF with no real blade surface inside the zone does essentially
  nothing** — confirmed empirically (velocities ~1000× smaller than the
  rotor tip speed, plateauing almost immediately — a numerical
  zone-interface artifact, not real flow). A cellZone alone, without a
  no-slip rotating surface for the fluid to actually interact with, will
  not spin up a fluid at rest.

## 4. Two-phase Eulerian-Eulerian (solid-liquid), `twoPhaseEulerFoam`

This was the highest-friction part of the whole project — the dictionary
schema is much less forgiving than single-phase, and best worked out by
cross-referencing `$FOAM_TUTORIALS/multiphase/twoPhaseEulerFoam/` directly
rather than guessing from memory.

- **Everything needs a matched pair, per phase.** Any field or solver
  entry needed for one phase (`T`, `alphat`, `k`, `epsilon`, `U`, `alpha`,
  its `fvSchemes`/`fvSolution` entries) is very likely needed for **both**
  phases, even when one seems physically inert (e.g. a laminar solid phase
  still needed `T.solid`/`alphat.solid` because of the shared
  `ThermalDiffusivity` base-class wrapping, independent of RAS/laminar
  choice).
- **`alpha` for BOTH phases must exist as real field files** — don't assume
  the solver derives the second one as `1 − alpha.first` automatically. We
  hit a real, physically-corrupting bug this way: `alpha.solid=0.20` with a
  missing `alpha.liquid` defaulting to `0` summed to `0.20` instead of
  `1.0`, and crashed the momentum equation construction with a floating
  point exception a few iterations in.
- **`phaseProperties` structure** (confirmed against
  `$FOAM_TUTORIALS/.../mixerVessel2D`):
  - `blending`: top-level, not nested per-force. `type none;
    continuousPhase liquid;` is correct for a fixed-loading dispersed solid
    that never approaches a flow-regime transition (no need for `linear`
    blending's `maxFullyDispersedAlpha`/`maxPartlyDispersedAlpha`, which is
    for systems that do transition, e.g. bubbly↔stratified).
  - `drag`: flat structure, no `type blended` wrapper needed — just
    `(solid in liquid) { type SchillerNaumann; residualRe ...;
    swarmCorrection {...} }` directly.
  - `sigma`: a phase-pair-keyed list of **plain numbers**, not a
    dimensionedScalar — `(liquid and solid) 0;`. Uses `and` (symmetric),
    not `in` (direction matters for drag, not for surface tension).
  - `aspectRatio ();`, `virtualMass ();`, `heatTransfer ();`, `lift ();`,
    `wallLubrication ();`, `turbulentDispersion ();` — present as empty
    lists even when physically irrelevant (e.g. rigid solid particles don't
    need `aspectRatio`, which is for deformable bubbles).
  - Each phase's own sub-dict needs `residualAlpha` (numerical floor,
    avoids divide-by-zero as a phase's local fraction → 0).
- **`RASModel` availability differs from the single-phase turbulence
  library.** `RNGkEpsilon` (available and used successfully in plain
  `simpleFoam`) is *not* compiled into the multiphase
  `PhaseCompressibleTurbulenceModel` library in this build — confirmed
  directly from the solver's own error listing valid types. Don't assume a
  single-phase model name carries over; check the error's own "valid types"
  list, it's authoritative.
- **Derived inlet BCs that need an auxiliary field
  (`turbulentIntensityKineticEnergyInlet` needing `U`,
  `turbulentMixingLengthDissipationRateInlet` needing `k`, wall functions
  like `nutkWallFunction`/`epsilonWallFunction` needing `k`) default to
  looking up an *unsuffixed* field name** (`U`, `k`) which doesn't exist in
  a multiphase case. Fix by adding an explicit override inside the BC
  itself, e.g. `k k.liquid;` / `U U.liquid;` alongside the BC's other
  entries.
- **`heRhoThermo` (even with `rhoConst` equation of state, i.e. genuinely
  incompressible-behaving phases) still formally requires the full
  compressible-thermo field set** — `p` (true static pressure, distinct
  from the solved `p_rgh`), `T` per phase, `alphat` per phase — even when
  energy/temperature isn't physically meaningful to the problem (keep
  `heatTransfer()` empty to prevent phases from actually exchanging heat,
  making the energy equation formally present but physically inert).

## 5. Debugging methodology that actually worked

- **One error at a time, verify each fix before moving to the next** —
  resist the urge to guess multiple fixes ahead; each error message from
  the solver is ground truth, memory/recollection of dictionary schemas is
  not.
- **When an error names valid options (e.g. "Valid RASModel types:
  (...)"), that list is authoritative** — use exactly what's listed, don't
  substitute a plausible-sounding alternative from a different solver
  family (we conflated `reactingEulerFoam`'s `continuous` blending type
  with `twoPhaseEulerFoam`'s, which doesn't have it).
- **When genuinely uncertain of a dictionary schema, check the actual
  installed source or a stock tutorial rather than continuing to guess**:
  - `find $WM_PROJECT_DIR -iname "*<keyword>*"` to locate the relevant
    source file, then read its `.H` file for the exact expected keywords.
  - `find $FOAM_TUTORIALS/<solverFamily> -type d` to find a structurally
    similar stock tutorial, then `cat` its dict files directly — this
    resolved several rounds of guessing in a single pass once we found
    `mixerVessel2D`.
  - `grep -rl "<keyword>" $WM_PROJECT_DIR/...` to confirm a specific
    keyword's real usage context before trusting a fix.
- **Verify claims computationally rather than asserting them** — e.g.
  ray-casting `locationInMesh` against the real STL, computing actual
  Reynolds numbers before choosing laminar vs turbulent, computing the
  actual outlet-port face-selection radius from STL geometry rather than
  assuming a round number, checking `phaseProperties`' actual chosen
  drag/turbulence values against the source paper's equations directly.
- **Package/deliver the working file set after every fix**, not just
  describe the change in prose — avoids drift between what's discussed and
  what's actually on disk.

## 6. Notes for the next project (different geometry, two-inlet both-liquid)

- The mesh/case separation, watertight-fluid-boundary STL strategy,
  `locationInMesh` ray-cast verification, and `topoSet`/`createPatch`
  patch-splitting pattern should all transfer directly to new geometry.
- A two-inlet, both-liquid case is structurally *simpler* than the
  solid-liquid build above — single-phase `pimpleFoam`/`simpleFoam`
  territory, just with an extra `inlet2`-style patch needing its own
  `flowRateInletVelocity`/turbulence-inlet BCs, no `twoPhaseEulerFoam`
  complexity, no per-phase field duplication. The single-phase lessons in
  section 3 are the relevant ones there, not section 4.
- If solid-liquid or any other multiphase work comes up again on the new
  geometry, section 4's `phaseProperties` structure (now cross-verified
  against a real stock tutorial) should be reusable close to as-is, adapted
  only for new phase names/properties.
