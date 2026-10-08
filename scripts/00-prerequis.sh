#!/usr/bin/env bash
# Vérifie que les outils nécessaires au POC sont installés.
set -uo pipefail

manquant=0
for outil in docker k3d kubectl helm git; do
  if command -v "$outil" >/dev/null 2>&1; then
    printf "  ✔ %-8s %s\n" "$outil" "$("$outil" version 2>/dev/null | head -n1)"
  else
    printf "  ✘ %-8s introuvable\n" "$outil"
    manquant=1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "  ✘ Docker ne répond pas : démarrez Docker."
  manquant=1
fi

[ "$manquant" -eq 0 ] && echo "Tout est prêt." || { echo "Installez les outils manquants puis relancez."; exit 1; }
