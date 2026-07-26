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

### Stopping / removing
```bash
docker stop <mycontainer>         # gracefully stop a running container
docker rm <mycontainer>           # delete it permanently (image is untouched)
```

## 3. Moving files in and out

```bash
docker cp myfile.txt <mycontainer>:/some/path/     # host -> container, one-off
docker cp <mycontainer>:/some/path/out.dat ./       # container -> host, one-off
```
For anything ongoing (your actual case files), prefer the **bind mount** (`-v`) set up when you first ran the container — it's a live, continuous shared folder, no copy step needed at all.

## 4. Running LONG simulations that survive you disconnecting

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
decomposePar
mpirun -np <N> icoFoam -parallel
reconstructPar      # merge parallel results back into single time directories
```

## 6. Quick troubleshooting checks

```bash
docker --version                  # confirm Docker itself is installed/working
docker info                       # daemon status, storage driver, resource limits
docker inspect <mycontainer>      # full JSON detail on a container (mounts, env, state)
docker stats                      # live CPU/memory usage per running container
```
