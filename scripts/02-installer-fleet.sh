#!/usr/bin/env bash
# Installe Fleet (sans Rancher) sur le cluster de gestion.
#
# Deux charts :
#   fleet-crd : les types (GitRepo, Bundle, BundleDeployment, Cluster, ClusterGroup...)
#   fleet     : fleet-controller + gitjob
#
# apiServerURL / apiServerCA : l'adresse que les AGENTS utiliseront pour joindre
# le cluster de gestion. On donne le nom interne du réseau Docker, pas localhost.
set -euo pipefail

MGMT=k3d-fleet-mgmt
API_INTERNE=https://k3d-fleet-mgmt-server-0:6443
CA_FICHIER=$(mktemp)

kubectl config view --raw --minify --context "$MGMT" \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$CA_FICHIER"

helm repo add fleet https://rancher.github.io/fleet-helm-charts/ >/dev/null 2>&1 || true
helm repo update fleet

helm --kube-context "$MGMT" upgrade --install fleet-crd fleet/fleet-crd \
  -n cattle-fleet-system --create-namespace --wait

helm --kube-context "$MGMT" upgrade --install fleet fleet/fleet \
  -n cattle-fleet-system --create-namespace --wait \
  --set apiServerURL="$API_INTERNE" \
  --set-file apiServerCA="$CA_FICHIER"

rm -f "$CA_FICHIER"

echo
kubectl --context "$MGMT" -n cattle-fleet-system get pods
echo
echo "Types ajoutés par Fleet :"
kubectl --context "$MGMT" api-resources --api-group=fleet.cattle.io
echo
echo "Fleet est installé. Suite : ./scripts/03-enregistrer-clusters.sh"
