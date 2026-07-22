# Base image: Ubuntu 18.04 ("bionic") -- the release OpenFOAM 5's packages
# actually target, confirmed earlier when we checked version compatibility.
FROM ubuntu:18.04

# Basic tools needed before we can even add OpenFOAM's own package repository.
RUN apt-get update && apt-get install -y wget software-properties-common

# Add OpenFOAM's repository key, add the repo itself, refresh package lists,
# then install openfoam5. This is the exact same sequence we discussed doing
# by hand -- just automated so it happens identically every build.
RUN wget -O - https://dl.openfoam.org/gpg.key | apt-key add - \
    && add-apt-repository http://dl.openfoam.org/ubuntu \
    && apt-get update \
    && apt-get install -y openfoam5

# Land in a sensible default folder when the container starts.
WORKDIR /root

# Default action when the container starts: just open a shell.
CMD ["/bin/bash"]
