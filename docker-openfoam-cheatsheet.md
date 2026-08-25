# Docker Command Reference — OpenFOAM Workflow

## 1. Images (the "recipe" / template)

```bash
docker images                     # list all images you have locally
docker build -t <name> .          # build an image from a Dockerfile in the current folder
docker rmi <image_name_or_id>     # delete an image (only if no container is using it)
docker image prune                # delete all UNUSED (dangling) images, frees disk space
```

## 2. Containers (a running/stopped instance of an image)

```bash
docker ps                         # list only RUNNING containers
docker ps -a                      # list ALL containers, including stopped ones
docker rm <container_name_or_id>  # delete a stopped container
docker container prune            # delete ALL stopped containers at once
```

### Starting a container for the first time
```bash
docker run -it --name <mycontainer> -v ~/openfoam-cases:/cases <image_name>
```
- `-it` : interactive + gives you a terminal
- `--name` : names it, so you can find/resume it later instead of creating a new one
- `-v host_path:container_path` : bind mount (shares a real folder with the container)

Check `docker inspect <original_container>` to see exactly how it was originally launched if you want to inspect/remember that setup.

#### - Activate the OpenFOAM environment (every new shell/session needs this)
```bash
source /opt/openfoam5/etc/bashrc
```

### Resuming a container you already created
```bash
docker start -ai <mycontainer>    # -a: attach output, -i: interactive (get your shell back)
```
**Use this, not `docker run`, once a named container already exists** — `docker run` always creates a brand-new container from the image; `docker start` resumes the exact one you already have, with anything you previously installed/compiled inside it still there.
#### - Activate the OpenFOAM environment (every new shell/session needs this)
```bash
source /opt/openfoam5/etc/bashrc
```

### Popping into an ALREADY RUNNING container (second window, doesn't disturb it)
```bash
docker exec -it <mycontainer> bash
```
Use this to check on a simulation that's currently running, without stopping it.

You can run this `docker exec` command as many times as you want, from as many separate terminal windows as you want — each one gives you a fresh shell session inside the same container, all sharing the same filesystem, mounted volumes, and case directories. So your second calculation can just `cd` to `new_case/` (or wherever) and run normally, completely independently of whatever's running in your first terminal session — no conflict, no setup needed.

### Stopping / removing
```bash
docker stop <mycontainer>         # gracefully stop a running container
docker rm <mycontainer>           # delete it permanently (image is untouched)
```

### One-shot / disposable containers (`--rm`)
Everything above assumes a *persistent* container you keep coming back to
— that's the right model for interactive work, but not every task needs
it. `--rm` tells Docker to delete the container automatically the moment
its command finishes, instead of leaving a stopped container sitting in
`docker ps -a` that you'd otherwise have to clean up by hand:
```bash
docker run --rm -v ~/openfoam-cases:/cases <image_name> \
    bash -c "source /opt/openfoam5/etc/bashrc && cd /cases/myCase && decomposePar"
```
**This is safe for anything using a bind mount, and here's precisely why**:
`--rm` only deletes the *container's own private storage* (whatever it
wrote outside `/cases`). It has zero effect on the bind-mounted folder,
because that data was never inside the container's own storage to begin
with — it's your host disk the whole time, just visible under a different
path name. Nothing under `-v ~/openfoam-cases:/cases` is ever at risk from
`--rm`.

Use `--rm` for: `decomposePar`, `reconstructPar`, `checkMesh`, quick
one-off checks — anything where you don't need the container itself to
stick around afterward. Keep using the persistent `--name` pattern above
for anything you're actively developing/debugging in.

## 3. Moving files in and out

```bash
docker cp myfile.txt <mycontainer>:/some/path/     # host -> container, one-off
docker cp <mycontainer>:/some/path/out.dat ./       # container -> host, one-off
```
For anything ongoing (your actual case files), prefer the **bind mount** (`-v`) set up when you first ran the container — it's a live, continuous shared folder, no copy step needed at all.

## 4. Running LONG simulations that survive you disconnecting
First, find out how many cores you actually have available, so run this inside the container.
```bash
nproc
```
This is the part that matters most for "large simulations" — by default, if you close your terminal or lose your SSH connection, a foreground process (like your solver) dies with it. Two ways to avoid that:

### Option A — run the whole container detached from the start
```bash
docker run -d --name <mycontainer> -v ~/openfoam-cases:/cases <image_name> \
  bash -c "source /opt/openfoam5/etc/bashrc && cd /cases/myCase && mpirun -np 4 icoFoam -parallel > log.run 2>&1"
```
- `-d` : detached — runs in the background immediately, doesn't hold your terminal
- Reattach anytime to check progress:
  ```bash
  docker logs -f <mycontainer>        # stream the container's output live
  ```

### Option B — you're already inside the container interactively, and want to background the run
Inside the container:
```bash
source /opt/openfoam5/etc/bashrc
cd /cases/myCase
nohup mpirun -np 4 icoFoam -parallel > log.run 2>&1 &
disown
```
- `nohup ... &` : runs the command in the background, immune to hangups
- `disown` : detaches it fully from your current shell session

Then **detach from the container without stopping it**:
```
Ctrl+P, then Ctrl+Q     (a key sequence, not typed as text)
```
This leaves the container (and your simulation) running, and drops you back to your host terminal. Come back anytime with:
```bash
docker attach <mycontainer>
```
or just check the log file directly (works whether you're attached or not, since it's in your bind-mounted folder):
```bash
tail -f ~/openfoam-cases/myCase/log.run
```

**Important**: never type plain `exit` inside a container that's running your solver in the *foreground* — that kills the shell and the process with it. `Ctrl+P, Ctrl+Q` (detach) is safe; `exit` is not, unless the job is already backgrounded with `nohup ... &`.

### Option C — detached AND self-cleaning (`-d --rm`), best for a genuinely unattended production run
Combines Sections 2's `--rm` with Option A's `-d`. Use this when you're
launching a run you don't intend to `exec` back into or fiddle with — just
fire it off, let it write results to the bind mount, check on it from the
host side, and let Docker clean up after itself when it's done:
```bash
docker run -d --rm --name of5_run -v ~/openfoam-cases:/cases <image_name> \
    bash -c "source /opt/openfoam5/etc/bashrc && cd /cases/myCase && \
    exec mpirun -np 4 pimpleFoam -parallel > log.run 2>&1"
```
**Note the `exec` before `mpirun` — this isn't optional if you want `docker stop` to work.** Without it, `mpirun` is a *child* of the `bash -c` process, and Docker's stop signal goes to `bash`, which does not automatically forward it to children it spawned — a genuine, well-known Docker gotcha, not a hypothetical. `exec` replaces the bash process with `mpirun` entirely, so `mpirun` becomes the container's actual PID 1 and receives the signal directly.

## 5. Everyday OpenFOAM-in-container workflow

```bash
# 1. Activate the OpenFOAM environment (every new shell/session needs this)
source /opt/openfoam5/etc/bashrc

# 2. Go to your case (in the bind-mounted folder, so it's visible on your host too)
cd /cases/myCase

# 3. Standard meshing + running sequence
blockMesh
checkMesh
icoFoam            # or whatever solver the case needs
# for parallel:
# 1. Split the mesh + fields into processorN/ directories.
#    system/decomposeParDict must exist, with numberOfSubdomains matching -np below.
decomposePar

# 2. Run the solver across N processes
mpirun -np <N> pimpleFoam -parallel | tee log.pimpleFoam

# 3. Merge the processorN/ results back into ordinary time directories
#    (needed before ParaView, postProcess, or anything else can read them normally)
reconstructPar -latestTime     # just the most recent time
reconstructPar                 # every saved timestep
```

### Stopping a long run cleanly (do this BEFORE reaching for `docker stop`)
If `controlDict` has `runTimeModifiable true` (worth always setting for any
run you might need to interrupt), you can tell the solver to stop cleanly
without touching Docker at all — just edit the live file, from the host,
since it's the same bind-mounted path:
```bash
sed -i 's/stopAt.*endTime;/stopAt          writeNow;/' ~/openfoam-cases/myCase/system/controlDict
```
The running solver notices the change, finishes and writes the *current*
timestep properly, then exits on its own — avoiding a truncated or
ambiguous latest-time directory, which is a real risk with any abrupt kill
(`docker stop`, a lost connection, a reboot). If you intend to resume the
run later, remember to set `stopAt` back to `endTime` and confirm
`startFrom latestTime;` before relaunching — no need to re-`decomposePar`,
since decomposition only depends on the mesh, which hasn't changed.

Only fall back to `docker stop <mycontainer>` (Section 2) if the graceful
route doesn't respond — and if it doesn't, check whether the launch command
included `exec` before `mpirun` (Section 4, Option C) first, since that's
the most common reason a stop signal doesn't land.

### Error: "mpirun has detected an attempt to run as root"
Containers commonly run everything as root, which Open MPI blocks by default (a safety
check meant for real shared multi-user systems — largely moot in a disposable container):
```bash
mpirun --allow-run-as-root -np 4 pimpleFoam -parallel | tee log.pimpleFoam
```

### Error: "plm_rsh_agent ... ssh : rsh ... could not be found"
Minimal container images often don't ship an `ssh` client, which Open MPI's default
launcher looks for even for single-node, local-only runs where it's never actually used.
Either option works, no reinstall needed:
```bash
# Option A: point at any harmless existing executable (never actually invoked locally)
mpirun --allow-run-as-root -mca plm_rsh_agent /bin/sh -np 4 pimpleFoam -parallel | tee log.pimpleFoam

# Option B: skip the ssh-based launcher entirely
mpirun --allow-run-as-root --mca plm ^rsh -np 4 pimpleFoam -parallel | tee log.pimpleFoam
```
To fix it permanently instead of flagging every command (if the container has network access):
```bash
apt-get update && apt-get install -y openssh-client
```

### Error: `make` hangs / "File '...' has modification time N s in the future"
Happens after copying/transferring solver source files onto a machine
whose clock is behind the one they were written on (e.g. via `scp`, or
files created on this machine and copied into a container with clock
drift) — `make`'s dependency tracking compares file timestamps to "now"
and can loop indefinitely instead of failing cleanly. Fix, run once inside
the solver's source directory before `wmake`:
```bash
find . -type f -exec touch {} +
```

## 6. Windows-artifact cleanup (`:Zone.Identifier` files)

If case files were ever downloaded/copied through a Windows filesystem (even briefly, e.g.
via `/mnt/c/...` in WSL) before landing in the container, Windows silently attaches an NTFS
"Alternate Data Stream" to each one, marking it as internet-downloaded. These can surface as
literal companion files (`myfile:Zone.Identifier`) that OpenFOAM tries and fails to read as
part of its normal directory scan — harmless, but noisy. Clean them out once:
```bash
find /path/to/case -name "*:Zone.Identifier" -delete
```

## 7. Quick troubleshooting checks

```bash
docker --version                  # confirm Docker itself is installed/working
docker info                       # daemon status, storage driver, resource limits
docker inspect <mycontainer>      # full JSON detail on a container (mounts, env, state)
docker stats                      # live CPU/memory usage per running container
```
A genuine solver failure (numerical divergence, bad input) always leaves either an
explicit `FOAM FATAL ERROR` block in the log, or truncated/garbage output
mid-timestep. A log that ends cleanly right after a fully normal, fully
converged timestep (no warnings, bounded residuals) — with nothing that
looks like an error — points to something *external* stopping it instead
(lost SSH connection without `nohup`/`-d`, `docker stop` without `exec`,
a host reboot, or the OOM/out of memory killer).
