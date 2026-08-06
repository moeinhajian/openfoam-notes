# Running OpenFOAM5 on MIT ORCD (Engaging) — Reference

Grounded directly against ORCD's own documentation (orcd-docs.mit.edu),
checked live rather than assumed. Written for reuse on future HPC runs.

## 1. Login and basics

```bash
ssh <kerberos-username>@orcd-login.mit.edu
```
(Kerberos password + Duo 2FA required.) Alternate login nodes exist
(`orcd-login002/003/004`) if one is slow — functionally identical.

**Storage**: you get three spaces — `home` (small, for scripts/config),
`$HOME/orcd/pool` (large, not optimized for heavy I/O), and
`$HOME/orcd/scratch` (fast flash storage — **use this for actual
simulation working directories**, not home). Files in
`orcd/scratch` are deleted if you haven't logged in for 6 months.

**Partitions available with no special PI access**:
- `mit_normal` — standard CPU partition, Rocky 8 nodes.
- `mit_normal_gpu` — GPU partition (not needed for this work).
- `mit_preemptable` — higher resource/time limits, but **jobs can be
  killed anytime the owning lab needs the nodes back**. Riskier for a
  long two-phase run; start with `mit_normal` for anything you can't
  afford to lose partway through.

## 2. Building the OpenFOAM5 image — confirmed, supported ORCD workflow

```bash
module load apptainer/1.4.2
```
(`module av apptainer` first if you want to check for a newer version.)
`singularity` and `apptainer` are the same binary on ORCD — interchangeable.

**Architecture check first**: if your existing Docker image was built on
an Apple Silicon Mac (M1/M2/M3/M4), it is ARM and will NOT run on
Engaging (x86). Building fresh from the `.def` file below sidesteps this
entirely, since it pulls a fresh x86 Ubuntu base directly on ORCD.

Save this as `openfoam5.def`:

```
Bootstrap: docker
From: ubuntu:18.04

%post
    apt-get update && apt-get install -y wget software-properties-common
    wget -O - https://dl.openfoam.org/gpg.key | apt-key add -
    add-apt-repository http://dl.openfoam.org/ubuntu
    apt-get update
    apt-get install -y openfoam5
    apt-get clean

%environment
    source /opt/openfoam5/etc/bashrc

%runscript
    exec /bin/bash "$@"
```

Build it (fakeroot is pre-enabled as part of the apptainer module — this
is ORCD's own documented, supported pattern, not a workaround):

```bash
apptainer build --fakeroot openfoam5.sif openfoam5.def
```

Do this **on a compute node, not the login node** — request a short
interactive session first:
```bash
salloc -p mit_normal --time=00:30:00
# once allocated:
module load apptainer/1.4.2
apptainer build --fakeroot openfoam5.sif openfoam5.def
```

**Worth checking before building from scratch**: ORCD maintains a shared
library of pre-built images and definition files at
`/orcd/software/community/001/container_images` — worth a quick look in
case someone's already built an OpenFOAM image there.

## 3. Quick interactive test

```bash
singularity exec openfoam5.sif simpleFoam -help
```
Because `%environment` sources OpenFOAM's `bashrc` automatically, you do
NOT need to manually source anything each time — unlike the Docker
workflow you were using on your PC.

## 4. Parallel batch job (SLURM)

`decomposeParDict` (`numberOfSubdomains 90; method scotch;`) should
already be in `system/` from the case files. Submit script:

```bash
#!/bin/bash
#SBATCH --job-name=twoPhaseEulerFoam
#SBATCH -t 48:00:00
#SBATCH -N 1                    # adjust if a single node has <90 cores
#SBATCH -n 90
#SBATCH -p mit_normal
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err

module load apptainer/1.4.2

CASE_DIR=$SLURM_SUBMIT_DIR
SIF=$CASE_DIR/openfoam5.sif

cd "$CASE_DIR"

# bind your scratch/pool storage if the case lives there, not under $HOME
singularity exec -B $HOME/orcd/scratch,$HOME/orcd/pool "$SIF" decomposePar -force

mpirun -np $SLURM_NTASKS singularity exec \
    -B $HOME/orcd/scratch,$HOME/orcd/pool "$SIF" \
    twoPhaseEulerFoam -parallel > log.twoPhaseEulerFoam 2>&1

singularity exec -B $HOME/orcd/scratch,$HOME/orcd/pool "$SIF" \
    reconstructPar -latestTime
```

```bash
sbatch run_twophase.sbatch
squeue -u $USER
tail -f slurm-<jobid>.out
```

Home and `/tmp` are bound into the container automatically — any other
path (like `orcd/scratch`/`orcd/pool`) needs the explicit `-B` flag shown
above, or the container won't see those files at all.

**Recommended first step**: request a short/small test allocation
(`--time=00:30:00`, maybe 8-16 cores) to confirm the whole
decompose→run→reconstruct pipeline works mechanically, before committing
a long 90-core allocation that might fail on something small 5 minutes in.

## 5. Getting results back to your PC for ParaView

No confirmed ORCD-hosted ParaView (checked; unlike some other university
clusters' OnDemand portals, nothing found specifically for Engaging) — so
the reliable path is: reconstruct on ORCD, then transfer the reconstructed
result down to your PC and use your existing local ParaView, same as
you've been doing all along.

**Don't transfer the raw `processorN/` directories** — only reconstruct,
then move the merged time directories. This is both much smaller and
avoids needing to run `reconstructPar` again locally.

Three confirmed transfer options:
1. **`rsync`/`scp` from your PC** (pulls, doesn't push, so run this on
   your own machine, not on ORCD):
   ```bash
   rsync -avz --progress \
     <username>@orcd-login.mit.edu:~/orcd/scratch/case_twophase/{0,constant,system,[1-9]*} \
     ./case_twophase_results/
   ```
   (the `{0,constant,system,[1-9]*}` pattern grabs the case setup plus all
   numeric timestep directories, skipping `processorN/` folders entirely.)
2. **Globus** — better for large transfers, handles interruptions/resumes
   gracefully; set up via the ORCD OnDemand portal if you expect this to
   be a large dataset.
3. **OnDemand File Browser** (`orcd-ood.mit.edu`) — simplest for smaller,
   one-off transfers, drag-and-drop in browser.

## 6. Routine for future runs

1. Build/reuse `openfoam5.sif` once — doesn't need rebuilding per case.
2. Copy your mesh + case directories into `$HOME/orcd/scratch/`.
3. `decomposePar`, submit via `sbatch`, monitor with `squeue`.
4. `reconstructPar -latestTime` once done (or periodically, if you want
   to check on a long run without waiting for full completion).
5. `rsync` the reconstructed results back to your PC.
6. Investigate in your local ParaView, same workflow as your PC-based runs.
