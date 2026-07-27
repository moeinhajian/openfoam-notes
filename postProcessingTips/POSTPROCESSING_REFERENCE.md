# Post-Processing Reference

Things done through OpenFOAM itself (automatable, works across every saved
timestep at once) 

---

## Part 1 — OpenFOAM-native (function objects)

### The one command that actually works, after several false starts

```bash
pimpleFoam -postProcess -dict system/flowRateCheck
```

**Use the solver binary's own `-postProcess` flag, not the generic `postProcess`
utility.** The generic utility repeatedly failed to find `U` in its field registry
(`Requested field U not found in database`) even though `U` is always saved to disk —
running through the actual solver binary uses its own `createFields.H` setup and doesn't
have this problem. This is the single most important lesson from this whole exercise:
**if a function object complains a field "is not found in database," try running it
through the solver binary's `-postProcess` flag instead of the generic `postProcess`
utility before assuming anything is wrong with the case.**

### Working `flowRateCheck` dict (flow rate in/out, over the whole saved run)

```cpp
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "system";
    object      flowRateCheck;
}

functions
{
    inletFlowRate
    {
        type            surfaceFieldValue;
        libs            ("libfieldFunctionObjects.so");
        regionType      patch;
        name            inlet;
        operation       areaNormalIntegrate;
        fields          (U);
        writeFields     false;
        log             true;
        writeControl    writeTime;
    }
    outletFlowRate
    {
        type            surfaceFieldValue;
        libs            ("libfieldFunctionObjects.so");
        regionType      patch;
        name            outlet_port;
        operation       areaNormalIntegrate;
        fields          (U);
        writeFields     false;
        log             true;
        writeControl    writeTime;
    }
}
```

Run: `pimpleFoam -postProcess -dict system/flowRateCheck`
Output: `postProcessing/inletFlowRate/.../surfaceFieldValue.dat` and the equivalent for
outlet — a clean `(time, flowRate)` table. Compare both against the prescribed
`1.217×10⁻⁸ m³/s`; they should converge to match (continuity check).

### Mandatory keywords that aren't obvious (all found the hard way)

- Every dict file needs the full `FoamFile{...}` header block — a bare `functions{...}`
  body alone gets rejected ("problem while reading header").
- `surfaceFieldValue` requires `writeFields` explicitly (true/false), even if you don't
  want the raw field written.
- Don't rely on `phi` existing in saved time directories — it isn't guaranteed to be
  written. Use `U` with `operation areaNormalIntegrate` instead (integrates the normal
  component of a vector field over a patch = flow rate), which sidesteps this entirely.

### Do this live, going forward, not retroactively

Paste the same `functions{}` block directly into `system/controlDict` **before**
starting a run (rather than analyzing after the fact via `-postProcess -dict`). Function
objects running live during the actual solve don't have any of the field-registry
issues above, since the fields are already in memory as the solver uses them.

### Torque / power on the impeller (not yet run, but ready)

```cpp
impellerForces
{
    type            forces;
    libs            ("libforces.so");
    patches         (impellerMoving impellerStationary);  // or just 'impeller' in the frozen-rotor case
    rho             rhoInf;
    rhoInf          1000;
    CofR            (0 0 0);
}
```
Z-component of the reported moment = torque about the rotation axis. Power = torque × ω.

### Reference numbers that don't change (no post-processing needed, already computed)

| quantity | value |
|---|---|
| Rotor tip Reynolds number | ≈43,600 (turbulent) |
| Inlet Reynolds number | ≈6.6 (essentially laminar) |
| Blade tip speed (analytic) | Ω×r ≈ 0.838 m/s at r=4mm |
| Rotor period | 30 ms (2000 rpm) |
| Full-domain residence time | ≈653 s |



