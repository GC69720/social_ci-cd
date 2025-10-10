#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; return 1; }; }

if [ -r /etc/os-release ]; then
  . /etc/os-release
else
  echo "Cannot detect OS"; exit 1
fi

echo "Detected: $NAME ($ID/$VERSION_ID)"

if [[ "$ID_LIKE" =~ (rhel|fedora|centos) ]] || [[ "$ID" =~ (rhel|rocky|almalinux|fedora|centos) ]]; then
  sudo dnf -y update
  # Node.js 20
  sudo dnf -y module reset nodejs || true
  sudo dnf -y module enable nodejs:20 || true
  sudo dnf -y install nodejs
  # Base tools
  sudo dnf -y install git make python3 python3-pip podman podman-docker podman-compose       postgresql redis
elif [[ "$ID_LIKE" =~ (debian|ubuntu) ]] || [[ "$ID" =~ (debian|ubuntu) ]]; then
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates gnupg lsb-release
  # NodeSource Node.js 20
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs git make python3 python3-pip podman podman-compose       postgresql redis-server
else
  echo "Unsupported distro. Install manually: podman, podman-compose, git, make, python3, pip, nodejs, postgresql, redis."; exit 1
fi

echo "All set. Next steps:"
echo "  make init"
echo "  make dev"
