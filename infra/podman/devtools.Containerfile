# infra/podman/devtools.Containerfile
FROM docker.io/library/node:20-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Add CLI tooling you need inside the devtools container
RUN apt-get update && apt-get install -y --no-install-recommends \
    git make curl ca-certificates \
    python3 python3-pip \
    postgresql-client redis-tools \
 && rm -rf /var/lib/apt/lists/*

# Node 20 already included; npm is recent enough -> no global npm upgrade needed
WORKDIR /workspace
