# Outlet Patch Splitting — Procedure & Reference Notes

## The problem

The original `fluid_regions_OF_m.stl` exported the entire top cap of the tank as a single
continuous patch named `outlet` — a smooth dome, ~1349 mesh faces, spanning from near the
central axis out to the tank wall. There was no small, distinct "port" feature baked into
the geometry; the whole dome was one opening.

**Goal:** keep only a small circular region near the axis (the real outlet port) as an
actual flow opening, and reclassify the rest of the dome as stationary tank wall.

## Why this can't be done from the STL/CAD alone

There's no natural seam in the geometry to split along — it's one smooth, continuously
curving surface. The split radius (5 mm) was a judgement call based on where the STL's own
facet geometry naturally started flattening near the crown, not a value derived from a
real design spec. This is a **mesh-level patch surgery** problem, not a re-meshing problem.

## The mechanism: two utilities, two different jobs

- **`topoSet`** — builds *sets* (labelled collections of cells or faces). It doesn't change
  the mesh at all; it just tags things for later use.
- **`createPatch`** — actually restructures the mesh's boundary, turning a faceSet into a
  real, independent patch.

They have to be run in that order, in the same directory, against the same mesh state.

## Key pitfalls hit along the way (useful to remember for future patch-splitting work)

1. **`cylinderToFace` does not exist** in OpenFOAM 5's `topoSet`. The available face-level
   sources are things like `patchToFace`, `boxToFace`, `cellToFace` — no direct cylindrical
   face selector. Workaround: build a *cellSet* with `cylinderToCell` (which does exist),
   then convert to a faceSet with `cellToFace`.

2. **`setsToZones` has no `-dict` flag.** Unlike `topoSet`, it always reads
   `system/setsToZonesDict` by convention and — more importantly — it does not read that
   dict selectively either. It scans `constant/polyMesh/sets/` and tries to convert
   *every* set object sitting there into a zone, including old diagnostic sets `checkMesh`
   may have written (`concaveCells`, `warpedFaces`, etc.). Always clear
   `constant/polyMesh/sets/` of anything you don't explicitly want converted before running it.

3. **`createPatch` is a one-shot, destructive operation.** Once it runs, the original
   source patch (`outlet`) is consumed/restructured — it no longer exists to select from
   again. If a `createPatch` run produces the wrong result, you cannot "retry" on the same
   mesh; you must regenerate the mesh from `snappyHexMesh` onward before attempting the
   split again.

4. **Don't let `createPatch` infer "the rest" via `constructFrom patches`.** The first
   attempt defined the small port via `constructFrom set` (an explicit faceSet) and the
   leftover dome via `constructFrom patches; patches (outlet);` (implicitly "whatever's
   left of the original patch"). These two definitions don't coordinate with each other
   within the same run — the result was one patch silently claiming *all* 1349 original
   faces and the other ending up with zero. **Fix:** build both faceSets explicitly and
   exhaustively in `topoSet` first (using an `action delete` step to compute the exact
   complement), then have `createPatch` build *both* new patches via `constructFrom set`,
   never `constructFrom patches`. No ambiguity left for the tool to resolve incorrectly.

## Final, working `topoSetDict` (outlet-related actions)

```cpp
// Cell-based selection near the axis, in the dome's Z-band
{
    name    outletPortCells;
    type    cellSet;
    action  new;
    source  cylinderToCell;
    sourceInfo { p1 (0 0 0.0075); p2 (0 0 0.0130); radius 0.005; }
}

// The small port: original outlet faces, subset to those near the axis
{
    name    outletPort;
    type    faceSet;
    action  new;
    source  patchToFace;
    sourceInfo { name outlet; }
}
{
    name    outletPort;
    type    faceSet;
    action  subset;
    source  cellToFace;
    sourceInfo { set outletPortCells; option all; }
}

// The explicit complement: original outlet faces, MINUS the port
{
    name    outletDome;
    type    faceSet;
    action  new;
    source  patchToFace;
    sourceInfo { name outlet; }
}
{
    name    outletDome;
    type    faceSet;
    action  delete;
    source  cellToFace;
    sourceInfo { set outletPortCells; option all; }
}
```

## Final, working `createPatchDict`

```cpp
patches
(
    {
        name            outlet_port;
        patchInfo       { type patch; }
        constructFrom   set;
        set             outletPort;
    }
    {
        name            domeWall;
        patchInfo       { type wall; }
        constructFrom   set;
        set             outletDome;
    }
);
```

## Full run sequence (from a clean mesh)

```bash
cd mesh
rm -rf constant/polyMesh constant/extendedFeatureEdgeMesh
surfaceFeatureExtract
blockMesh
snappyHexMesh -overwrite
checkMesh -allTopology -allGeometry

rm -f constant/polyMesh/sets/*
topoSet                      # builds rotor cellSet + outletPort/outletDome faceSets
createPatch -overwrite       # materializes outlet_port and domeWall as real patches
rm -f constant/polyMesh/sets/outletPort constant/polyMesh/sets/outletPortCells constant/polyMesh/sets/outletDome
setsToZones                  # converts the remaining 'rotor' cellSet into a cellZone
checkMesh
```

## Verification (don't skip — trust the actual output, not the log alone)

```bash
grep -A5 "^    outlet_port$" constant/polyMesh/boundary
grep -A5 "^    domeWall$" constant/polyMesh/boundary
awk '/^rotor$/{f=1} f && /^[0-9]+$/{print $0; exit}' constant/polyMesh/cellZones
```

Expect: `outlet_port` with roughly ~360 faces, `domeWall` with roughly ~990 faces
(they should sum to the original outlet's 1349), and `rotor` cellZone at 469 cells.

## Result sizes actually observed

| set/zone | size |
|---|---|
| `rotor` (cellZone) | 469 cells |
| `outlet` (original, before split) | 1349 faces |
| `outletPort` | 359 faces (~27%) |
| `outletDome` | 990 faces (~73%) |
