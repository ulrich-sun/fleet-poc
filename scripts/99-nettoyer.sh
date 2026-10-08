#!/usr/bin/env bash
# Supprime les 3 clusters et le réseau Docker du POC.
set -uo pipefail
k3d cluster delete fleet-mgmt dev prod
docker network rm fleet-net >/dev/null 2>&1 || true
echo "POC supprimé."
