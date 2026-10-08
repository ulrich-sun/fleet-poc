#!/usr/bin/env bash
# Crée le ClusterGroup « production » et le GitRepo qui lance toute la chaîne.
set -euo pipefail

: "${REPO_URL:?Définissez REPO_URL, ex. REPO_URL=https://github.com/vous/fleet-poc}"
BRANCHE=${BRANCHE:-main}
MGMT=k3d-fleet-mgmt
ICI=$(cd "$(dirname "$0")/.." && pwd)

kubectl --context "$MGMT" apply -f "$ICI/manifests/clustergroup.yaml"

sed -e "s#__REPO_URL__#${REPO_URL}#" -e "s#__BRANCHE__#${BRANCHE}#" \
  "$ICI/manifests/gitrepo.yaml" | kubectl --context "$MGMT" apply -f -

echo
echo "GitRepo créé. Fleet va cloner $REPO_URL ($BRANCHE)."
echo "Observez : ./scripts/05-observer.sh"
