# Running OpenFOAM5 on MIT ORCD (Engaging) via Apptainer — Reference

Built from an actual, real debugging session — every fix here was verified
against either ORCD's own documentation or an actual error message, not
assumed. Written for reuse on future HPC runs, and as a general reference
for understanding containers on HPC.

---

## Part 1 — Concepts (read this once, applies to any future container work)

### "Linux" is a kernel, not one operating system

ORCD's Engaging cluster runs **Rocky Linux 8**. OpenFOAM5's official
install method is a `.deb` package from an **Ubuntu/Debian**-specific
repository. These are both "Linux," but that only means they share a
kernel — the package manager (`apt` vs `dnf`), core library versions, and
file layout are all different, non-interchangeable ecosystems on top of
that shared kernel. This mismatch is *why* containers are the right tool
here, not a workaround: a container bundles a complete, self-contained
Ubuntu **userspace** (libraries, `apt`, file layout) that runs on top of
whatever kernel the host machine actually has — which works specifically
because the Linux kernel's system-call interface stays compatible across
distributions, even though the distros riding on it are otherwise quite
different. ORCD's own docs state this directly: *"Users can use
Singularity to obtain the Ubuntu OS rather than the Rocky 8 OS on the
host cluster."*

The alternative — compiling OpenFOAM5 from source directly against
Rocky 8's own libraries — is possible but a materially bigger
undertaking (matching compilers, resolving each dependency by hand) than
staying in the container path, especially once you already have a
working Ubuntu-based Docker setup on your PC.

### Image vs. container — the distinction that actually matters day to day

- **Image** (`.sif` file on ORCD, or a Docker image on your PC) — a
  **permanent, ordinary file**. Build it once; it sits on disk like any
  other file until you delete or rebuild it. It has nothing to do with
  individual job submissions.
- **Container** — a **temporary, running instance** of that image,
  created fresh and torn down automatically every time you invoke
  `singularity exec`/`run`/`shell`. You do **not** rebuild the image for
  each job — a SLURM script's `singularity exec openfoam5.sif ...` line
  creates one new lightweight instance per job run, reusing the same
  permanent `.sif` file every time.

This is exactly analogous to Docker's own `docker build` (once) vs.
`docker run` (as many times as you want) — the concept transfers
directly.

### Docker (PC) vs. Apptainer/Singularity (ORCD) — what's actually different

| | Docker | Apptainer |
|---|---|---|
| Privilege model | Background daemon with root — why HPC clusters ban it | No persistent daemon; `--fakeroot` only simulates root inside a sandboxed namespace during build, safe for shared systems |
| Image format | Multi-layer, Docker's internal storage | Single portable file (`.sif`) |
| Isolation | Fairly isolated from host by default | Deliberately more porous — auto-binds home dir, cwd, `/tmp` so HPC workflows (reading/writing shared storage) work without extra flags |
| Commands | `docker run/build/exec` | `singularity`/`apptainer run/build/exec` — same concepts, different verbs |

Mental model: swap `docker run` for `singularity exec`, everything else
about image-vs-instance thinking carries over unchanged.

---

## Part 2 — ORCD basics

```bash
ssh <kerberos-username>@orcd-login.mit.edu
```
Kerberos password + Duo 2FA. Alternate login nodes (`orcd-login002/3/4`)
exist if one is slow.

**Storage**: `home` (small), `$HOME/orcd/pool` (large, not high-I/O
optimized), `$HOME/orcd/scratch` (fast flash — use this for actual
simulation working directories). Files in `orcd/scratch` are deleted
after 6 months of inactivity.

**Partitions with no special PI access needed**: `mit_normal` (standard
CPU, Rocky 8), `mit_normal_gpu` (GPU, not needed here), `mit_preemptable`
(higher limits but jobs can be killed anytime the owning lab needs the
nodes — risky for a long run).

```bash
module load apptainer/1.5.2
```
`singularity` and `apptainer` are the same binary — interchangeable.

---

## Part 3 — Two ways to get the image onto ORCD

### Path A: Build natively on ORCD from a `.def` file

**Status as of this session: not completed, but the blocking issue was
fully diagnosed and fixed — likely one attempt away from working, if you
want to revisit it.** Abandoned in favor of Path B partly out of
practicality (Path B was already known-good on the PC side), not because
Path A was fundamentally broken.

The `.def` file (a direct translation of the Dockerfile):
```
Bootstrap: docker
From: ubuntu:18.04

%setup
    # ORCD's apptainer module injects APPTAINER_BINDPATH=/orcd,/nfs -
    # confirmed directly via `env | grep -i bind`, not guessed. Neither
    # path exists in a minimal ubuntu:18.04 image, so each bind mount
    # fails until pre-created here. %setup runs on the HOST, as root,
    # before these mounts are attempted - $APPTAINER_ROOTFS points at
    # the container filesystem on disk.
    mkdir -p ${APPTAINER_ROOTFS}/nfs
    mkdir -p ${APPTAINER_ROOTFS}/orcd

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

```bash
apptainer build --fakeroot openfoam5.sif openfoam5.def
```

**Debugging notes, in case you revisit this:**
- The bind paths are **not** in the static `/etc/apptainer/apptainer.conf`
  (checked directly via `grep -i "bind path"` — only `/etc/localtime` and
  `/etc/hosts` are actually active there, both harmless). They come from
  the **`apptainer/1.5.2` module itself**, injected as the
  `APPTAINER_BINDPATH` environment variable. `env | grep -iE
  "bind|apptainer|singularity"` is the reliable way to get the complete,
  authoritative list — much better than discovering paths one fatal error
  at a time.
- `--no-mount bind-paths` does **not** exist as a flag for `apptainer
  build` (verified against the official CLI reference) — that was a
  wrong guess early in debugging this; don't try it.

### Path B: Build the image on your PC (Docker), transfer, convert — the path actually used

No `%post`/fakeroot/bind-path issues apply here at all, since nothing
privileged runs on ORCD's side — this is a pure format conversion.

**1. On your PC — confirm architecture, then export:**
```powershell
docker image inspect openfoam5-test:latest --format "{{.Architecture}}"
# must print amd64 - Docker Desktop on Windows builds amd64 by default,
# so this is expected to pass (unlike Docker on Apple Silicon Macs,
# which would build arm64 and NOT run on Engaging's x86 hardware)

docker save openfoam5-test:latest -o openfoam5-test.tar
```

**2. Transfer to ORCD** (rsync preferred over scp for a multi-GB file —
resumable if interrupted):
```bash
rsync -avz --progress openfoam5-test.tar <username>@orcd-login.mit.edu:~/orcd/scratch/
```

**3. Convert to `.sif` — do this on a COMPUTE node, not the login node:**
```bash
salloc -p mit_normal --time=00:30:00 --mem=8G
# once allocated:
module load apptainer/1.5.2
cd ~/orcd/scratch
apptainer build openfoam5.sif docker-archive://openfoam5-test.tar
```

**Why a compute node matters here — real error hit and fixed:**
running this on the login node failed with:
```
FATAL ERROR: Failed to create thread
```
from `mksquashfs` (the tool that compresses the final `.sif`). Cause:
login nodes carry restrictive `ulimit -u` (max processes/threads) since
they're not meant for heavy computation, and `mksquashfs` defaults to
spawning one compression thread per CPU core. Fix: run on a compute node
(above), or if you need to push through without an allocation, cap the
thread count directly:
```bash
apptainer build --mksquashfs-args="-processors 2" openfoam5.sif docker-archive://openfoam5-test.tar
```

**4. Test:**
```bash
singularity exec openfoam5.sif bash -c "source /opt/openfoam5/etc/bashrc && simpleFoam -help"
```
Note: since the original Dockerfile never auto-sourced OpenFOAM's
bashrc (just `CMD ["/bin/bash"]`), the converted `.sif` doesn't either —
you still need `source /opt/openfoam5/etc/bashrc &&` before each command,
same as the existing Docker habit on the PC. (Path A's `.def` file, by
contrast, *does* auto-source via its `%environment` section — a small
extra convenience Path A would have had, if pursued to completion.)

---

## Part 4 — Running the parallel job

`decomposeParDict` should already be in `system/` (`numberOfSubdomains
90; method scotch;`).

```bash
#!/bin/bash
#SBATCH --job-name=twoPhaseEulerFoam
#SBATCH -t 48:00:00
#SBATCH -N 1                    # adjust if a single node has <90 cores
#SBATCH -n 90
#SBATCH -p mit_normal
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err

module load apptainer/1.5.2

CASE_DIR=$SLURM_SUBMIT_DIR
SIF=$CASE_DIR/openfoam5.sif

cd "$CASE_DIR"

singularity exec -B $HOME/orcd/scratch,$HOME/orcd/pool "$SIF" \
    bash -c "source /opt/openfoam5/etc/bashrc && decomposePar -force"

mpirun -np $SLURM_NTASKS singularity exec \
    -B $HOME/orcd/scratch,$HOME/orcd/pool "$SIF" \
    bash -c "source /opt/openfoam5/etc/bashrc && twoPhaseEulerFoam -parallel" \
    > log.twoPhaseEulerFoam 2>&1

singularity exec -B $HOME/orcd/scratch,$HOME/orcd/pool "$SIF" \
    bash -c "source /opt/openfoam5/etc/bashrc && reconstructPar -latestTime"
```

```bash
sbatch run_twophase.sbatch
squeue -u $USER
tail -f slurm-<jobid>.out
```

Home and `/tmp` are bound automatically; any other path (`orcd/scratch`,
`orcd/pool`) needs the explicit `-B` flag above.

**Recommended first step**: a short/small test allocation (`--time=00:30:00`,
8-16 cores) to confirm decompose→run→reconstruct works mechanically before
committing the full 90-core allocation.

---

## Part 5 — Getting results back for ParaView

No confirmed ORCD-hosted ParaView found (checked; some other university
clusters' OnDemand portals have this, nothing found for Engaging
specifically) — transfer results back to your PC and use your existing
local ParaView.

**Reconstruct first, then transfer only the merged timestep
directories** — never the raw `processorN/` folders (much larger, and
useless without reconstruction anyway).

```bash
# run FROM your PC, not on ORCD (rsync/scp pull, don't push)
rsync -avz --progress \
  <username>@orcd-login.mit.edu:~/orcd/scratch/case_twophase/{0,constant,system,[1-9]*} \
  ./case_twophase_results/
```
Alternatives: Globus (better for large/interruptible transfers), OnDemand
File Browser (`orcd-ood.mit.edu`, simplest for small one-off transfers).

---

## Part 6 — Routine for future runs

1. Build/reuse `openfoam5.sif` once — no rebuild needed per case.
2. Copy mesh + case directories into `$HOME/orcd/scratch/`.
3. `decomposePar`, submit via `sbatch`, monitor with `squeue`.
4. `reconstructPar -latestTime` once done (or periodically on a long run).
5. `rsync` reconstructed results back to your PC.
6. Investigate in local ParaView, same workflow as PC-based runs.

---

## Appendix — troubleshooting log from this session (for future reference)

| symptom | cause | fix |
|---|---|---|
| `mount /nfs->/nfs error: destination doesn't exist` | ORCD's apptainer module injects `APPTAINER_BINDPATH`, target dirs missing in minimal Ubuntu image | `%setup: mkdir -p ${APPTAINER_ROOTFS}/nfs` (and `/orcd`, same pattern) |
| `--no-mount: unknown command` | Flag doesn't exist for `apptainer build` (only for exec/run/shell) | Don't use it; use the `%setup` approach above |
| `FATAL ERROR: Failed to create thread` during `apptainer build ... docker-archive://` | Login node's restrictive thread/process `ulimit`, hit by `mksquashfs`'s default one-thread-per-core behavior | Build on a compute node (`salloc`), or `--mksquashfs-args="-processors 2"` |
| Confused about which paths need pre-creating | Static config (`/etc/apptainer/apptainer.conf`) looked relevant but wasn't the real source | `env \| grep -iE "bind\|apptainer\|singularity"` gives the authoritative, complete list directly |
