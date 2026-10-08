#!/usr/bin/env bash
# Affiche la chaîne complète, maillon par maillon, du dépôt Git jusqu'aux pods.
set -uo pipefail

MGMT=k3d-fleet-mgmt
NS=fleet-default
titre() { printf "\n\033[1;36m━━ %s ━━\033[0m\n" "$1"; }

titre "1. GitRepo (quel commit a été cloné ?)"
kubectl --context "$MGMT" -n "$NS" get gitrepo \
  -o custom-columns='NOM:.metadata.name,DEPOT:.spec.repo,COMMIT:.status.commit,PRETS:.status.display.readyBundleDeployments'

titre "2. Bundles (un par dossier contenant un fleet.yaml)"
kubectl --context "$MGMT" -n "$NS" get bundles \
  -o custom-columns='BUNDLE:.metadata.name,PRETS:.status.display.readyClusters,ETAT:.status.display.state'

titre "3. Clusters et leurs étiquettes (= ce qui décide du ciblage)"
kubectl --context "$MGMT" -n "$NS" get clusters.fleet.cattle.io --show-labels

titre "4. ClusterGroups"
kubectl --context "$MGMT" -n "$NS" get clustergroups

titre "5. BundleDeployments (un par couple bundle × cluster)"
kubectl --context "$MGMT" get bundledeployments -A \
  -o custom-columns='NAMESPACE (=cluster):.metadata.namespace,BUNDLE:.metadata.name,ETAT:.status.display.state'

for c in dev prod; do
  titre "6. Résultat sur le cluster $c"
  echo "Releases Helm créées par l'agent :"
  helm --kube-context "k3d-$c" list -A 2>/dev/null | grep -v cattle-fleet || true
  echo
  kubectl --context "k3d-$c" get deploy -n accueil 2>/dev/null
  kubectl --context "k3d-$c" get deploy -n podinfo 2>/dev/null
done
