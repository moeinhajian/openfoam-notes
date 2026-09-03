# Running Calculations on This Workstation — Quick Reference

This is the *operational* runbook: what to actually type, every time, and
why. For the technical/physics reasoning behind the case setup itself, see
`PROJECT_INSTRUCTIONS.md` instead — this file is only about the
Docker/run-management mechanics.

**Fill these in once for this machine, then never think about them again:**

| Placeholder | Your value | How to find it |
|---|---|---|
| `<IMAGE>` | | `docker images` |
| `<HOST_DIR>` | `~/openfoam-cases` (your established convention) | — |
| `<N>` | | `nproc` (leave 1-2 cores free) |

---

## 0. The one idea that explains everything below

`-v <HOST_DIR>:/cases` is a **bind mount** — not a copy. `<HOST_DIR>` on
your machine and `/cases` inside the container are the *same physical
files* under two different path names. The solver writes to `/cases/case/...`
inside the container; that write lands directly on your normal disk at
`<HOST_DIR>/case/...`. There is no sync step, no export, no "getting results
out of the container" — they were never only *in* the container.

This is why you never need a shell inside the container just to check on
things: `tail -f`, `scp`, `monitor_rtd.py`, all work directly against
`<HOST_DIR>` on the host, live, while the container is still running.

---

## 1. One-time setup (only redo if starting fresh on a new machine)

```bash
# on the ORIGINAL machine
docker save openfoam5-mrfsolver:latest -o openfoam5-mrfsolver.tar
scp openfoam5-mrfsolver.tar you@new-workstation:/path/to/somewhere/

# on THIS new machine
docker load -i openfoam5-mrfsolver.tar
docker images    # confirm it now shows up here
```
If you already ran `docker build` directly on this new machine (using the Dockerfile + solver source folder from earlier), just confirm it's there: `docker images`

```bash
mkdir -p <HOST_DIR>
# transfer mesh/, case/, solver/ from wherever they currently live, e.g.:
scp -r you@other-machine:~/openfoam-cases/* <HOST_DIR>/
```

**Check if the solver is already baked into the image:**
```bash
docker run --rm <IMAGE> bash -c "source /opt/openfoam5/etc/bashrc && which twoLiquidMixingMRFFoam"
```
- Prints a path -> solver is baked in, skip the next block entirely.
- Empty/not found -> this is the plain base image; compile once per fresh
  container (see `PROJECT_INSTRUCTIONS.md` Section 6 for why `make` may
  also need installing first — same base image gap discovered in the dev
  container).

---

## 2. Every time you want to run a calculation

### Step A — Decompose (only if the mesh or core count changed since last time)

*Why:* parallel runs need the mesh pre-split into `processor0..N-1/`
directories. Re-running this over an *already-progressing* run would
destroy that progress — never run it if `<HOST_DIR>/case/processor0/`
already has meaningful time directories in it from a run you want to keep.

```bash
# edit numberOfSubdomains in <HOST_DIR>/case/system/decomposeParDict to <N> first

docker run --rm -v <HOST_DIR>:/cases <IMAGE> \
    bash -c "source /opt/openfoam5/etc/bashrc && cd /cases/case && decomposePar"
```
*Flags used, and why:* no `-it` (nothing to type into), no `-d` (fast,
just wait for it), `--rm` (throwaway — nothing worth keeping in the
container itself, results go straight to the bind mount).

### Step B — Launch the actual run

*Why these flags specifically:* `-d` because this runs for hours/days and
you want your terminal back; `--rm` because nothing inside the container
itself is worth keeping (again — results live on the host via the bind
mount, not in the container); `--name` so you can find/check/stop it later
by name instead of a random ID; `exec` before `mpirun` so `mpirun` becomes
the container's actual PID 1 and can receive stop signals directly (without
`exec`, `docker stop` may not reach it at all — a real Docker gotcha, not
a hypothetical one).

```bash
docker run -d --rm --name of5_run -v <HOST_DIR>:/cases <IMAGE> \
    bash -c "source /opt/openfoam5/etc/bashrc && cd /cases/case && \
    exec mpirun -np <N> twoLiquidMixingMRFFoam -parallel > log.twoLiquidMixingMRFFoam 2>&1"
```

### Step C — Monitor it (from your normal host terminal, no container interaction needed)

```bash
tail -f <HOST_DIR>/case/log.twoLiquidMixingMRFFoam   # raw solver log
docker logs -f of5_run                                # same thing, via Docker
docker ps                                             # confirm it's still running at all

# RTD progress specifically:
python3 monitor_rtd.py <HOST_DIR>/case --watch 300
```

### Step D — Stop it

**Graceful (preferred — use this whenever you plan to restart later):**
edit the live `controlDict` directly from the host (no container
interaction needed — it's the same bind-mounted file):
```bash
sed -i 's/stopAt.*endTime;/stopAt          writeNow;/' <HOST_DIR>/case/system/controlDict
```
`runTimeModifiable true` (already set) makes the running solver notice this
change, finish the *current* timestep cleanly, write it, and exit — avoiding
a truncated/ambiguous latest-time directory (this is exactly the ambiguity
we had to resolve carefully once already, after an unplanned interruption).
**Remember to change `stopAt` back to `endTime` before the next run.**

**Force stop (fallback, if graceful doesn't respond):**
```bash
docker stop of5_run
```

### Step E — Reconstruct and retrieve

```bash
docker run --rm -v <HOST_DIR>:/cases <IMAGE> \
    bash -c "source /opt/openfoam5/etc/bashrc && cd /cases/case && reconstructPar -latestTime"

# then, from your PC:
rsync -avz you@this-workstation:<HOST_DIR>/case ./local-copy/
```

### Step F — Resume later (same run, more time)

*Why no re-decompose needed:* decomposition only depends on the mesh, which
hasn't changed. Confirm `startFrom latestTime;` is set in `controlDict`
(it should already be), set `stopAt` back to `endTime`, then repeat Step B
exactly as before.

---

## Quick troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `make` infinite loop / "modification time in future" | Clock skew from a file transfer | `find <solver dir> -type f -exec touch {} +` before `wmake` |
| Parallel run hangs/crashes at startup | `numberOfSubdomains` != actual `-np` used | Check both match `<N>` exactly |
| `docker stop` doesn't stop it | Missing `exec` before `mpirun` in the launch command | Add `exec`, relaunch (can't fix a running container after the fact — must relaunch with the corrected command) |
| Container not found by name | Already exited (check `docker ps -a` for exit reason) or typo in `--name` | `docker ps -a`, check `docker logs of5_run` for why it stopped |
