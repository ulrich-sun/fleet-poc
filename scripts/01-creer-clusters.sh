#!/usr/bin/env bash
# Crée 3 clusters k3d sur un même réseau Docker, pour qu'ils puissent se joindre par nom :
#   fleet-mgmt : cluster de gestion (fleet-controller)
#   dev, prod  : clusters en aval (fleet-agent)
# Le --tls-san ajoute le nom DNS interne au certificat de l'API, sinon la connexion
# entre clusters échouerait sur une erreur de certificat.
set -euo pipefail

RESEAU=fleet-net

for c in fleet-mgmt dev prod; do
  if k3d cluster list "$c" >/dev/null 2>&1; then
    echo "Cluster $c déjà présent, on passe."
    continue
  fi
  echo "Création du cluster $c..."
  k3d cluster create "$c" \
    --network "$RESEAU" \
    --servers 1 --agents 0 \
    --k3s-arg "--tls-san=k3d-${c}-server-0@server:0" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait
done

echo
kubectl config get-contexts | grep k3d-
echo "Les 3 clusters sont prêts. Suite : ./scripts/02-installer-fleet.sh"
