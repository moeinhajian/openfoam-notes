# Project Instructions — Two-Inlet, Dual-Impeller Baffled Mixing Tank (CFD Learning Project)

## 1. Project goal

Investigate the mixing performance of a two-inlet (feed + second stream),
baffled, dual-impeller stirred tank, staged in increasing physical complexity:

1. **Stage A** — validate the hydrodynamics/mixing pattern with no dispersed
   phase and no reaction chemistry. **Currently active stage.**
2. **Stage B** — add the physics that actually match the real fluid pair
   (dispersed droplets via MP-PIC, or a resolved interface via VOF, depending
   on what Section 7 determines about miscibility).
3. **Stage C** — couple a population balance equation (PBE) for particle/
   droplet/crystal size distribution, reproducing the methodology of
   Kim et al. (2020, 2021) and/or Rosa & Braatz (2018a) on our own geometry.

Modeled on, but not a direct copy of, the reference library in Section 4.

---

## 3. Geometry, scale, and derived operating conditions (established)

Source: 7 STL components (`tank_wall`, `baffle1`, `baffle2`, `impeller`,
`inlet1`, `inlet2`, `outlet`).

- **Axis convention**: Z is the axial/rotation direction. Origin (X=0, Y=0)
  is the shaft centerline. Z=0 is the tank bottom.
- **Scale, final and confirmed**: raw uploaded STL coordinates ARE real mm —
  no scaling needed. Cross-checked two ways: (a) matches the physical scale
  described in Aprile et al. 2026 (TWC paper, Section 4); (b) tank volume
  computed directly from the `tank_wall.stl` mesh via the divergence theorem
  (not a bounding-box approximation) = **7.51 mL**, closely matching that
  paper's single-tank (TWC-1) volume of 8 mL.
- **Exact geometry (from vertex data, not bounding boxes)**:
  - Tank: max radius 14.15 mm (NOT a simple cylinder — has a shaft-bushing
    feature down to 2.3 mm radius), height 25.161 mm.
  - Impeller: blade-tip radius **5.829 mm** (exact), shaft spans Z=0.41 to
    25.161 mm. Two blade stages, clustered at Z≈5-8mm and Z≈18-21mm — vertex-
    density-confirmed, not a single impeller.
  - Baffles: inner edge radius **6.500 mm** (exact) — i.e. only a 0.671 mm
    radial gap to the impeller tip. Diametrically opposed, full height.
  - Inlets: diameter 1.8 mm, mirrored about X=0, at Z≈11.76-13.56 mm
    (between the two impeller stages), ~90° azimuthally offset from baffles.
  - Outlet: top-center (Z=25.161mm), concentric with the shaft — shaft top
    nearly coincides with the outlet plane (flagged mesh-watertightness risk).
  - No valid symmetry plane — rotation breaks any static mirror symmetry
    even though the layout itself is mirror-symmetric. Full 3D domain.
- **Derived operating conditions** (Stage A, methanol feed / water
  antisolvent, no solute): scaled from Aprile et al. 2026's TWC-1 single-tank
  condition by the tank-volume ratio (7.51/8 mL):
  - Impeller: **2000 rpm** (209.44 rad/s) — chosen by matching tip speed
    (~1.2 m/s) to the paper's benchmarking condition, valid because our
    impeller diameter (11.46mm) is within ~10% of theirs (10.2-11mm).
  - `inlet1` (methanol): 0.0845 mL/min -> 1.4083e-9 m3/s.
  - `inlet2` (water): 0.0376 mL/min -> 6.267e-10 m3/s.
  - Mean residence time ~ 61.5 min; run >=4 residence times before treating
    results as steady (matches the paper's own stated convergence check).
  - **Finding, not an assumption**: at these flow rates, inlet velocity
    (~5e-4 m/s) is 2-3 orders of magnitude below any impeller-driven
    velocity scale — mixing in this tank is impeller-dominated, inlet jet
    momentum is negligible. This is a checkable prediction of the case, not
    a modeling shortcut.

---

## 4. Reference library

| Paper | System studied | Phase model | OpenFOAM version / code | Primary contribution to this project |
|---|---|---|---|---|
| **Kim, Lee & Braatz (2020)**, *Comput. Chem. Eng.* 134 | Antisolvent crystallization, biradial mixer | Euler (fluid) + Lagrangian (crystal parcels), MP-PIC-PBE | OF 5.0, built on `DPMFoam` | Defines MP-PIC-PBE method; parcel-based PBE; when/why Lagrangian over Eulerian for a dispersed phase |
| **Rosa & Braatz (2018a)**, *Ind. Eng. Chem. Res.* 57 ("openCrys") | Antisolvent crystallization, 3 mixer geometries | Single-phase Eulerian, 3-environment PDF micromixing + spatial PBE | OF 5.0, `github.com/darosacezar/openCrys` | Eulerian PBE alternative to Kim's Lagrangian route; variable-property mixing implementation |
| **Rosa & Braatz (2018b)**, *Ind. Eng. Chem. Res.* 57 (radial mixers) | Antisolvent crystallization, radial inlet count/velocity study | Same as 2018a, earlier build | OF 2.3 (superseded by 2018a's OF 5.0 build) | Systematic inlet-configuration study — directly relevant methodology for our two-inlet layout |
| **Kim, Lee & Braatz (2021)**, *Comput. Chem. Eng.* 152 | PMMA suspension polymerization, single pitched-blade impeller CSTR | Euler + Lagrangian (droplet parcels), MP-PIC-PBE + polymerization kinetics | OF 7.0, `github.com/KAIST-LENSE/mppicPbePolyFoam` | Only paper with a real rotating impeller — MRF setup, SST k-w justification, blade-angle mixing study, immiscible dispersed-droplet (not VOF) treatment |
| **Aprile et al. (2026)**, *Cryst. Growth Des.* ("TWC/Zaiput") | Ketoconazole antisolvent crystallization, tower crystallizer cascade vs. single-tank MSMPR | Experimental (not CFD) — RTD, micromixing time, tip speed characterization | N/A (experimental) | **Scale/operating-condition reference for Stage A** — our tank geometry matches their TWC-1 single-tank scale (~8mL, ~10-11mm impeller) far better than their MSMPR (~100mL); provided the RPM and flow-rate derivation in Section 3 |

**OF version fork, resolved for now**: Kim 2020's and Rosa's PBE code target
**OF 5.0**; Kim 2021's targets **OF 7.0**. Stage A is being built on **OF 5.0**
specifically so it stays compatible with Kim 2020/Rosa's PBE codebases for
Stage C — this is now a committed decision, not just a leaning (see Section 6
for the solver actually being used).

---

## 5. Staged solver architecture

| | **Stage A: miscible, no PBE** (ACTIVE) | **Stage B1: immiscible, dispersed droplets, no PBE** | **Stage B2: immiscible, resolved interface** | **Stage C1: miscible + PBE** | **Stage C2: immiscible + PBE** |
|---|---|---|---|---|---|
| Solver | **`twoLiquidMixingFoam`** (OF5 stock) -> patched to **`twoLiquidMixingMRFFoam`**, see Section 6 | MP-PIC (`DPMFoam`-derived), Kim 2021-style | `interFoam`/VOF family | Kim 2020 / Rosa 2018a | Kim 2021 (full) |
| Why this solver, not others in `multiphase/` | See Section 6 — VoF family assumes a sharp interface (wrong: these liquids mix); Euler-Euler family (`multiphaseEulerFoam`, `twoPhaseEulerFoam`, `reactingEulerFoam`) assumes interphase slip/drag (wrong: no relative velocity between miscible liquids, and much more expensive) | Kim 2021, PBE+reaction stripped | none of the 4 papers — new territory | Kim 2020 / Rosa 2018a | Kim 2021 (full) |
| OF version | **OF 5.0** | OF 5.0 or 7.0 (strip PBE calls) | any (stock `interFoam`) | **OF 5.0** | **OF 7.0** |
| Rotating zone | **MRF, patched in manually — see Section 6** | MRF strongly preferred (parcel cell-search needs stable cell ownership) | MRF or AMI | MRF | MRF (confirmed in Kim 2021) |
| Turbulence | k-e (default for now); SST k-w available if blade-surface fidelity becomes the bottleneck | SST k-w (Kim 2021) | k-e per phase | k-e (Kim 2020/Rosa) | SST k-w |
| Energy equation | off | often dropped (isothermal) | needed if phases differ in T | needed (heat of mixing/crystallization) | optional |

---

## 6. Established technical lessons (carried forward, still binding)

From the prior single-phase/impeller project:

- Separate `mesh/` and `case/` directories; `mesh/` needs its own minimal
  `fvSchemes`/`fvSolution` for `snappyHexMesh`'s internal solve.
- `locationInMesh` must be verified, not guessed — **now done by actual
  ray-casting against the STL** (Moller-Trumbore, 3 independent directions),
  not just bounding-box reasoning. Re-verify after any geometry change.
- Geometric patch *type* (`wall` vs `patch`) is separate from field BC *type*.
- Splitting a patch: build both `faceSet`s explicitly via `topoSet`.
- `createPatch` is one-shot and destructive.
- A closed domain needs `pRefCell`/`pRefValue`; this tank has a real
  `fixedValue` outlet, so it's inactive — confirmed, not assumed.
- MRF requires an actual no-slip blade surface inside the `cellZone`.

New this stage:

- **STL units are not auto-converted by OpenFOAM meshing utilities.**
  `blockMesh`'s `convertToMeters` only applies to `blockMeshDict`'s own
  vertices — `snappyHexMesh` reads referenced STL files as literal numbers.
  If the STL is mm-valued and the background mesh is meter-valued, you get a
  silent 1000x mesh-size error, no warning thrown. Fix: pre-scale STL files
  to be meter-valued before meshing; keep a separate mm-valued copy only for
  visualization/reference.
- **Background mesh box must exceed the TRUE max radius, not the bounding-box
  radius**, if the geometry isn't a perfect cylinder (ours isn't — see
  Section 3). Caught by computing exact vertex radii, not by inspection.
- **`twoLiquidMixingFoam` (stock OF5) has no MRF support** — verified via
  `grep -c MRF UEqn.H createFields.H pEqn.H` on the actual installed solver
  (all zero). Patched manually into a new solver `twoLiquidMixingMRFFoam`,
  built by mirroring `interFoam`'s confirmed-real MRF hooks (fetched and
  diffed from `OpenFOAM/OpenFOAM-5.x` on GitHub, not from memory):
  - `createFields.H`: add `IOMRFZoneList MRF(mesh);` after `createPhi.H`.
  - `UEqn.H`: add `MRF.correctBoundaryVelocity(U);` before the matrix is
    assembled, and `+ MRF.DDt(rho, U)` inside it.
  - `pEqn.H`: add `MRF.makeRelative(phiHbyA);` right after `phiHbyA` is
    built, and use the 5-argument `constrainPressure(p_rgh, U, phiHbyA,
    rAUf, MRF)` overload. **`MRF.correctBoundaryVelocity(U)` does NOT belong
    in `pEqn.H`** — an early draft of this patch had it there too; caught
    and removed after diffing against real fetched `interFoam` source.
  - `multiphaseEulerFoam` (N-phase solver) does the equivalent job
    differently: `MRF.correctBoundaryVelocity()` is called once per phase in
    a loop (`MRFCorrectBCs.H`), and the frame-acceleration term is computed
    as an **explicit field** via `MRF.addAcceleration()` (`DDtU.H`) rather
    than injected as an implicit matrix term via `MRF.DDt()` — because
    interfacial force closures need to *read* that acceleration as data.
    Relevant precedent for Stage C, not needed for Stage A.
  - Verification method used, reusable for future patches: (1) fetch the
    real current source of a structurally-similar stock solver that already
    has the feature, (2) diff the actual installed unpatched solver against
    it to see the true delta, (3) grep the class header itself
    (`$WM_PROJECT_DIR/src/finiteVolume/cfdTools/general/MRF/
    IOMRFZoneList.H`) for the authoritative API, (4) let `wmake` be the
    final check — a compiler error is worth more than either party's
    confidence.
- **Docker/OF5 container persistence — Option B chosen, not A.** Not
  overriding `WM_PROJECT_USER_DIR` inside the container (that stays at its
  ephemeral default). Instead, solver source lives permanently on the bind
  mount at `<project root>/solver/twoLiquidMixingMRFFoam/` (project root
  under the host-mounted path, container side `/cases`), alongside `mesh/`
  and `case/`. `wmake` does **not** require source to live under
  `$WM_PROJECT_USER_DIR/applications/solvers/` — that's a convention, not a
  requirement; `wmake` just needs `Make/files`+`Make/options` in the current
  directory, builds its object/dependency cache locally, and installs the
  binary via `$FOAM_USER_APPBIN` (resolved from the environment, wherever
  that currently points). **Consequence of this choice**: the compiled
  binary itself is ephemeral (lost on container restart, since
  `FOAM_USER_APPBIN` was never redirected to the mount) — re-run `wmake` in
  the solver directory once per fresh container session (fast, since only 3
  files differ from stock). Source safety does not depend on this.
- **`twoLiquidMixingMRFFoam` compiled clean** — zero compiler/linker
  errors, confirming the MRF patch's function signatures/includes are
  structurally correct (a wrong signature would have failed here, not
  silently). Runtime physical-sanity checks (rotor cellZone cell count,
  impeller boundary velocity non-uniform and consistent with Ω×r,
  MRF-vs-stock-tutorial comparison) are still the way to confirm the
  *physics* is right, not just the code.
- **Cold-start divergence, root-caused, not guessed.** First real transient
  run diverged (Courant number exploding from ~0 to ~2e14 within 2
  timesteps). Initial hypothesis (impulsive MRF start-up shock) was
  contradicted by the evidence itself — divergence appeared before the
  impeller had rotated even 1°, ruling it out. Actual cause, confirmed by
  comparing against a working Rosa-lineage reference `fvSchemes`/
  `fvSolution` for the same problem class: (1) `k`/`epsilon` initialized at
  an arbitrary near-zero `1e-6` instead of a physically-estimated value from
  tip speed (`k = 1.5*(I*U_tip)^2`, `epsilon` from the standard mixing-
  length formula) — day-one bounding warnings were the tell; (2) unbounded
  `Gauss linear` gradients in a mesh with very steep local gradients (tight
  tip-gap cells) — fixed with `cellLimited leastSquares 1`; (3) zero PIMPLE
  relaxation and only 2 `nOuterCorrectors` — insufficient for a stiff
  startup transient, fixed with 0.3 relaxation on `U`/`k`/`epsilon`/`p_rgh`
  and `nOuterCorrectors` raised to 50 (only needed for the cold-start step;
  drops to single digits once spun up — confirmed via `PIMPLE: converged in
  N iterations` in the log, not assumed).
- **Fundamental timescale-separation problem, confirmed with measured data,
  not just estimated.** Impeller rotation period (~0.03s at 2000rpm) vs.
  mean residence time (~3690s) is a ~5-order-of-magnitude gap. Courant-
  limited `deltaT` at full rotation speed is fixed by the tip-gap cell size
  regardless of mesh "looseness" (coarsening reduces per-timestep cost via
  fewer total cells, NOT the timestep size itself, which is geometrically
  constrained). Measured wall-clock cost at `maxCo 0.5`: ~78,200 s
  wall-clock per simulated second (~36,600 years to reach the 4-residence-
  time target — clearly infeasible as configured). Raising `maxCo`/
  `maxAlphaCo` to 1 gave a measured **~28x speedup** (not just the ~2x from
  larger `deltaT` alone — most of the gain came from needing far fewer
  PIMPLE outer iterations once flow was spun up), bringing it to ~2,800 s
  wall-clock per simulated second (~24.6 days for a 760s/~0.2-residence-time
  run). Full 4-residence-time target still needs either much higher `maxCo`,
  a steady-MRF-then-frozen-flow-field strategy, or accepting a much shorter
  simulated-time target for this stage's actual purpose.
- **HPC deployment: new image layered on the existing verified one, never
  modifying it.** `FROM openfoam5-test:latest` in a new `Dockerfile`
  (installs `make`, copies the solver source, runs `wmake` at BUILD time
  so the shipped image is immutable and ready-to-run — no compile step at
  job launch, unlike the local Option B workflow). Built, saved
  (`docker save`), transferred, converted with `apptainer build
  <name>.sif docker-archive://<name>.tar` — same conversion pattern already
  proven working for the prior project's image.
- **HPC submit script — sed-synced `numberOfSubdomains`, restart-safe
  `decomposePar` guard.** Reused the exact working Apptainer/MPI bridging
  pattern from the prior `twoPhaseEulerFoam` runs (solver name and
  `$SIF_DIR` changed only). `decomposeParDict`'s `numberOfSubdomains` is
  synced to `$SLURM_NTASKS` via `sed` at submit time (removes the
  manual-edit drift risk); the script checks for an existing `processor0/`
  before decomposing, since re-running `decomposePar` over an
  already-progressing run's `processor*/` directories would destroy that
  progress — this guard exists specifically because of the ambiguity we had
  to resolve by reading the log carefully after the local PC-restart
  incident. `case/system/controlDict` should use `startFrom latestTime;`
  (not a hardcoded `startTime 0`) for HPC runs, so a resubmission after any
  interruption resumes automatically. **Not yet done**: an actual test
  submission to confirm the whole chain works end-to-end on the cluster.
- **Parallel restart does not require re-running `decomposePar`** if the
  processor count is unchanged — decomposition depends only on the mesh and
  `decomposeParDict`, neither of which changed. Only re-decompose (or use
  `redistributePar` to reshuffle without a full serial round-trip) when
  changing core count between runs.
- **`incompressibleTwoPhaseMixture` field-naming convention — a second real
  mistake, caught by the solver's own fatal errors, not by review.** The
  alpha field file must be named `alpha.<firstPhaseName>` (i.e.
  `alpha.methanol`, matching `phases (methanol water);` in
  `transportProperties`), NOT the generic `alpha1` — the C++ variable is
  called `alpha1` internally but the on-disk field name is phase-name-based.
  A second, related trap in the same area: **`fvSchemes`'s div-scheme
  lookup for the alpha transport term uses the literal hardcoded key
  `alpha` (group suffix stripped), not the real field name** —
  `div(phi,alpha)`/`div(phirb,alpha)`, NOT `div(phi,alpha.methanol)`. Two
  different lookup mechanisms in the same solver, two different expected
  keys — the fatal error message is authoritative for each; do not infer
  one from the other. (Confirmed independently: an unrelated real
  Rosa-lineage `fvSchemes` also uses the bare `alpha` key, consistent with
  this being the general convention, not solver-specific.)
- **Distinguishing a real solver crash from an external interruption in the
  log.** A genuine physics/numerical failure always produces either an
  explicit `FOAM FATAL ERROR` block or truncated/garbage mid-timestep
  output. A log that ends cleanly right after a fully-normal, fully-
  converged timestep (no warnings, bounded residuals/continuity errors,
  `PIMPLE: converged`) with no error block is evidence of an *external*
  kill (reboot, walltime, node failure) — but confirm OOM-kill specifically
  via `dmesg | grep -i oom` before assuming it was "just" a reboot, since
  both produce the same clean-stop signature in the OpenFOAM log itself.
- **HPC image build — `$HOME`-independent install location, CONFIRMED via
  direct diagnostic on the real cluster, not just theorized.** The original
  `ENV LOGNAME=root` / `ENV USER=root` Dockerfile fix was solving the wrong
  variable: on the HPC, Apptainer/Singularity preserved the baked `$USER`
  and `$LOGNAME` (`root`, as set) but **reset `$HOME` to the real host
  account regardless** (`/home/moeinhzd`, not `/root`). Since
  `$WM_PROJECT_USER_DIR` is derived from `$HOME` (not `$USER`/`$LOGNAME`),
  this alone broke it — `wmake` had installed the custom solver at
  `/root/OpenFOAM/root-5.0/.../bin` (Docker-build-time `$HOME`), while the
  cluster resolved `$FOAM_USER_APPBIN` to
  `/home/moeinhzd/OpenFOAM/root-5.0/.../bin` (nonexistent) at runtime. This
  is why the stock `twoLiquidMixingFoam` was findable on HPC but the custom
  `twoLiquidMixingMRFFoam` wasn't: stock solvers live under `$FOAM_APPBIN`
  (derived from `$WM_PROJECT_DIR=/opt/openfoam5`, fixed inside the image,
  `$HOME`-independent), while ours lived under the `$HOME`-dependent path.
  **Working fix**: in the Dockerfile's `wmake` step, `export
  FOAM_USER_APPBIN=$FOAM_APPBIN` and `export FOAM_USER_LIBBIN=$FOAM_LIBBIN`
  before building, so the custom solver installs into the same
  `$HOME`-independent global bin/lib as the stock solvers — works
  identically under Docker, Apptainer, or anything else, with no reliance
  on `$HOME`/`$USER`/`$LOGNAME` ever being preserved correctly.
  `decomposeParDict` uses `method scotch` (no geometric tuning needed for
  this mesh); `numberOfSubdomains` must be manually kept equal to
  `$SLURM_NTASKS` — see the "not yet automated" note below.
- **RTD cannot be extracted from a short simulated-time run** — not a "just
  need more patience" issue but a structural one: at t=13s vs. τ≈3690s
  (0.35% of one residence time), no tracer has had time to reach the
  outlet. The case IS already a valid step-tracer RTD setup (constant
  `alpha.methanol=1` at `inlet1` since t=0), so no new setup is needed once
  enough simulated time is reached — but the cheaper route once the
  velocity field is spun up to a statistically steady rotating pattern is
  **Lagrangian particle tracking on the frozen flow field**, since particle
  trajectory integration isn't bound by the same tip-gap Courant limit as
  the full PDE timestep.

---

## 7. Open items

- **Reaching the full 4-residence-time (14760s) target** — still unresolved.
  Options on the table: push `maxCo` well beyond 1 (PIMPLE is implicit, so
  this trades local temporal accuracy for throughput rather than risking
  hard instability); steady-MRF-then-frozen-flow-field + cheaper scalar/
  particle transport; or redefine this stage's target to a much shorter
  simulated time if a full residence-time RTD isn't actually needed yet.
- **HPC job — image built, submit script corrected, not yet run to
  completion.** Next concrete step: submit, confirm `twoLiquidMixingMRFFoam`
  actually starts (watch for `Creating MRF zones` in the log), let it run
  long enough to get a real multi-day throughput number on HPC hardware to
  compare against the measured local rate.
- **Miscibility of the REAL feed/second-stream pair** (as opposed to the
  methanol/water placeholder chemistry used to derive Stage A's operating
  conditions) — still the single highest-leverage unresolved question, since
  it forks the entire B/C solver lineage.
- **`Dab` (mutual diffusivity) in `transportProperties`** is a generic
  liquid-liquid order-of-magnitude placeholder (1.6e-9 m2/s), not a verified
  methanol-water value — real value is composition-dependent. Fine for
  qualitative Stage A flow-pattern results; revisit before trusting
  quantitative mixing-time numbers.
- **Mesh convergence study** — scoped (3 refinement levels, global QOIs:
  power number / max epsilon; local QOIs: velocity profile at blade tip, y+
  distribution) but not yet run against the actual mesh. Now additionally
  constrained by the throughput problem above — a finer mesh makes an
  already-expensive timestep worse, so this may need to wait until the
  timescale-separation strategy is settled.
- **`k`/`epsilon` inlet BCs** are placeholder-reasonable (low turbulence
  intensity) given the negligible-inlet-momentum finding in Section 3 — low
  priority to refine further given that finding.
- **Turbulence model**: currently k-e by default; SST k-w (Kim 2021
  precedent) not yet adopted — revisit once/if impeller-blade-surface y+
  fidelity becomes the limiting factor.
- **RTD extraction strategy** — decide between (a) brute-force outlet
  `alpha.methanol` tracking once/if a long enough run is achieved, or
  (b) Lagrangian particle tracking on a frozen converged flow field
  (cheaper, decouples from the PDE Courant limit). Leaning (b) given the
  throughput numbers above.

---

## 8. Learning log — concepts to make sure get properly explained along the way

- [x] MRF vs. AMI (sliding mesh) — physical difference, when each is valid
- [x] How MRF is actually implemented in OpenFOAM source (frame-acceleration
      term, relative-flux convention) — went deeper than originally scoped,
      via direct source patching
- [ ] RANS decomposition and why it's needed vs. DNS/LES for this Re range
- [ ] k-e vs. SST k-w — what each resolves better and why (Menter 1994)
- [ ] PIMPLE algorithm (PISO + SIMPLE) — what each sub-step solves for
- [ ] MP-PIC vs. Euler-Euler vs. VOF — the actual physical criterion for
      choosing between dispersed-phase representations (partially covered
      via the "why twoLiquidMixingFoam not X" discussion — revisit formally
      when Stage B miscibility is resolved)
- [ ] Population balance equation fundamentals — nucleation/growth/
      breakage/coalescence kernels, method of moments vs. sectional/
      class methods
- [ ] Kolmogorov turbulence scaling and its role in breakage-rate kernels
      (Coulaloglou & Tavlarides 1977, used in Kim 2021 Eq. 56)
- [ ] Relevant dimensionless numbers as they become relevant (Re, We, Da,
      residence time distribution) and what physical competition each one
      quantifies
