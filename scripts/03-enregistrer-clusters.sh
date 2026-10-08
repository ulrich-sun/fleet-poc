#!/usr/bin/env bash
# Enregistre dev et prod dans Fleet en mode « initié par le gestionnaire » :
#   1. on stocke le kubeconfig du cluster en aval dans un Secret (clé "value")
#   2. on crée un objet Cluster qui pointe vers ce Secret, avec des ÉTIQUETTES
#   3. fleet-controller s'en sert UNE fois pour installer le fleet-agent là-bas
#   4. ensuite, c'est l'agent qui contacte le gestionnaire (pull), plus l'inverse
#
# Les étiquettes (env=dev / env=prod) sont la base de TOUT le ciblage.
set -euo pipefail

MGMT=k3d-fleet-mgmt
NS=fleet-default

kubectl --context "$MGMT" create namespace "$NS" --dry-run=client -o yaml | kubectl --context "$MGMT" apply -f -

for c in dev prod; do
  echo "Enregistrement de $c (env=$c)..."
  # kubeconfig de $c, réécrit pour utiliser l'adresse interne au réseau Docker
  KUBECONFIG_INTERNE=$(k3d kubeconfig get "$c" \
    | sed -E "s#server: https://[^ ]+#server: https://k3d-${c}-server-0:6443#")

  kubectl --context "$MGMT" -n "$NS" create secret generic "kubeconfig-$c" \
    --from-literal=value="$KUBECONFIG_INTERNE" \
    --dry-run=client -o yaml | kubectl --context "$MGMT" apply -f -

  cat <<EOF | kubectl --context "$MGMT" apply -f -
apiVersion: fleet.cattle.io/v1alpha1
kind: Cluster
metadata:
  name: $c
  namespace: $NS
  labels:
    env: $c
spec:
  kubeConfigSecret: kubeconfig-$c
EOF
done

echo
echo "Attente des agents (jusqu'à 3 min)..."
for i in $(seq 1 36); do
  prets=$(kubectl --context "$MGMT" -n "$NS" get clusters.fleet.cattle.io \
    -o jsonpath='{range .items[*]}{.status.agent.lastSeen}{"\n"}{end}' 2>/dev/null | grep -c . || true)
  [ "$prets" -ge 2 ] && break
  sleep 5
done

kubectl --context "$MGMT" -n "$NS" get clusters.fleet.cattle.io --show-labels
echo
echo "Agent installé sur dev :"
kubectl --context k3d-dev -n cattle-fleet-system get pods
echo
echo "Suite : publiez le dossier dans Git, puis REPO_URL=... ./scripts/04-deployer-gitrepo.sh"
