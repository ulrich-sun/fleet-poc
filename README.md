# POC Fleet (Rancher) — comprendre toute la logique

Objectif : voir de vos yeux **chaque maillon** de la chaîne GitOps de Fleet, sur 3 clusters locaux.

```
                        ┌──────────────── Cluster de gestion (k3d fleet-mgmt) ────────────────┐
  Dépôt Git  ──clone──▶ │ GitRepo ──(gitjob + fleet apply)──▶ Bundles ──(ciblage)──▶ BundleDeployments │
  (GitHub)              │                                                     │          │       │
                        └─────────────────────────────────────────────────────┼──────────┼───────┘
                                                                pull (agent)  │          │  pull (agent)
                                                                              ▼          ▼
                                                                  ┌── k3d dev ──┐  ┌── k3d prod ──┐
                                                                  │ fleet-agent │  │ fleet-agent  │
                                                                  │ helm install│  │ helm install │
                                                                  └─────────────┘  └──────────────┘
```

## 1. La logique en 6 étapes (à lire avant de lancer)

1. **GitRepo** : vous déclarez « surveille ce dépôt, cette branche, ces dossiers, pour ces clusters ».
2. **Clonage** : le contrôleur *gitjob* lance un Job qui clone le dépôt à chaque nouveau commit (polling ou webhook).
3. **Bundles** : chaque dossier contenant un `fleet.yaml` (ou chaque chemin listé) devient un **Bundle** :
   un paquet de ressources + des options de déploiement. Nom = `<gitrepo>-<chemin>`.
4. **Ciblage** : Fleet croise les `targets` du GitRepo (et les `targetCustomizations` du `fleet.yaml`)
   avec les **étiquettes des clusters** et les **ClusterGroups**.
5. **BundleDeployments** : pour chaque couple (Bundle, cluster ciblé), Fleet crée un BundleDeployment
   dans un namespace dédié au cluster (`cluster-fleet-default-<cluster>-<hash>`), avec les valeurs déjà résolues.
6. **Agent** : le `fleet-agent` de chaque cluster **tire** ses BundleDeployments, les rend en release Helm
   (même le YAML brut et Kustomize deviennent une release Helm !), les applique, puis remonte l'état.

> Point clé : le cluster de gestion ne « pousse » jamais rien. Ce sont les agents qui viennent chercher leur travail.
> C'est ce qui permet à Fleet de gérer des milliers de clusters derrière des pare-feu.

## 2. Contenu du POC

```
fleet-poc/
├── scripts/
│   ├── 00-prerequis.sh          vérifie docker, k3d, kubectl, helm, git
│   ├── 01-creer-clusters.sh     3 clusters k3d sur un réseau Docker commun
│   ├── 02-installer-fleet.sh    Fleet (CRD + contrôleur) sur le cluster de gestion
│   ├── 03-enregistrer-clusters.sh  enregistre dev et prod (mode « initié par le gestionnaire »)
│   ├── 04-deployer-gitrepo.sh   crée le ClusterGroup et le GitRepo
│   ├── 05-observer.sh           affiche toute la chaîne d'objets et le résultat sur chaque cluster
│   └── 99-nettoyer.sh           supprime tout
├── manifests/
│   ├── clustergroup.yaml        groupe « production » (env=prod)
│   └── gitrepo.yaml             le GitRepo (l'URL est injectée par le script)
└── fleet-repo/                  ← ce que Fleet lit dans Git
    ├── 01-socle/                YAML brut : namespace + ConfigMap commune
    ├── 02-accueil-kustomize/    Kustomize : base + overlays dev/prod
    └── 03-podinfo-helm/         Helm : chart externe podinfo, valeurs par environnement
```

Chaque bundle illustre un mécanisme :

| Bundle | Format | Mécanisme démontré |
|---|---|---|
| `01-socle` | YAML brut | bundle le plus simple, étiquette `couche: socle` |
| `02-accueil-kustomize` | Kustomize | overlay différent selon le cluster, `dependsOn` le socle |
| `03-podinfo-helm` | Helm externe | `targetCustomizations`, ClusterGroup, templating `${ .ClusterName }`, `correctDrift` |

## 3. Prérequis

- Docker, [k3d](https://k3d.io) v5+, kubectl, helm v3, git
- Un compte GitHub (ou GitLab) pour héberger un dépôt **public** (le plus simple pour un POC)
- ~4 Go de RAM libres

## 4. Lancer le POC

```bash
cd fleet-poc
chmod +x scripts/*.sh

./scripts/00-prerequis.sh
./scripts/01-creer-clusters.sh
./scripts/02-installer-fleet.sh
./scripts/03-enregistrer-clusters.sh
```

Publiez ensuite **tout le dossier `fleet-poc`** dans un nouveau dépôt public :

```bash
git init -b main && git add . && git commit -m "POC Fleet"
git remote add origin https://github.com/<vous>/fleet-poc.git
git push -u origin main
```

Puis :

```bash
REPO_URL=https://github.com/<vous>/fleet-poc ./scripts/04-deployer-gitrepo.sh
./scripts/05-observer.sh      # relancez-le autant de fois que voulu
```

Après 1 à 2 minutes, vous devez voir sur **dev** : 1 réplique podinfo et 1 nginx ; sur **prod** : 3 répliques podinfo et 2 nginx.

Pour voir podinfo dans le navigateur :

```bash
kubectl --context k3d-prod -n podinfo port-forward svc/podinfo 9898:9898
# http://localhost:9898  → le message affiche le nom du cluster et son environnement
```

## 5. Expériences guidées (c'est là qu'on comprend)

### Expérience 1 — Suivre la chaîne d'objets
```bash
kubectl --context k3d-fleet-mgmt -n fleet-default get gitrepo poc -o yaml   # status.commit = le SHA cloné
kubectl --context k3d-fleet-mgmt -n fleet-default get bundles                 # 1 bundle par dossier
kubectl --context k3d-fleet-mgmt get bundledeployments -A                      # 1 par (bundle × cluster) = 6
kubectl --context k3d-fleet-mgmt -n fleet-default get bundle poc-fleet-repo-03-podinfo-helm -o yaml
```
Observez dans le BundleDeployment de prod que `replicaCount: 3` est **déjà résolu** : le ciblage est fait côté gestion, l'agent ne fait qu'appliquer.
```bash
helm --kube-context k3d-prod list -A    # chaque bundle est une release Helm, même le YAML brut
```

### Expérience 2 — Un commit = un déploiement
Modifiez `replicaCount` de prod dans `fleet-repo/03-podinfo-helm/fleet.yaml`, puis `git commit` + `git push`.
Dans les 15 s (`pollingInterval`), `status.commit` du GitRepo change, puis les pods suivent.

### Expérience 3 — Correction de dérive
```bash
kubectl --context k3d-prod -n podinfo scale deploy podinfo --replicas=1
kubectl --context k3d-prod -n podinfo get deploy podinfo -w
```
podinfo a `correctDrift.enabled: true` : l'agent remet 3 répliques. Faites la même chose sur `accueil`
(qui n'a pas `correctDrift`) : le bundle passe à l'état **Modified** et Fleet vous le signale sans corriger.

### Expérience 4 — Le ciblage, c'est juste des étiquettes
```bash
kubectl --context k3d-fleet-mgmt -n fleet-default label cluster dev env=prod --overwrite
```
dev reçoit maintenant la configuration de prod (3 répliques, overlay prod) **sans aucun commit**.
Remettez `env=dev` pour revenir en arrière.

### Expérience 5 — Dépendances
`02-accueil-kustomize` déclare `dependsOn` sur tout bundle étiqueté `couche: socle`.
Cassez volontairement le socle (remplacez `apiVersion: v1` par `apiVersion: v99` dans `01-socle/configmap.yaml`), poussez :
le socle passe en erreur (**ErrApplied**) et le bundle accueil reste en attente de sa dépendance au lieu de se mettre à jour.
Consultez `status.conditions` du bundle accueil pour lire le message d'attente.

### Expérience 6 — Mettre en pause
```bash
kubectl --context k3d-fleet-mgmt -n fleet-default patch gitrepo poc --type merge -p '{"spec":{"paused":true}}'
```
Poussez un changement : Fleet génère les nouveaux bundles mais ne les déploie pas. Repassez `paused` à `false`.

### Expérience 7 — Passer à l'échelle
Ajoutez un 3ᵉ cluster `staging` (copiez les lignes de dev dans les scripts 01 et 03, étiquette `env=dev`).
Il reçoit automatiquement tout ce qui cible `env=dev`. C'est exactement ainsi que Fleet gère 1 000 clusters.

## 6. Dépannage rapide

| Symptôme | Où regarder |
|---|---|
| GitRepo ne clone pas | `kubectl -n fleet-default get jobs,pods` puis les logs du pod gitjob |
| Cluster jamais « Ready » | `kubectl --context k3d-dev -n cattle-fleet-system logs deploy/fleet-agent` |
| Bundle en `ErrApplied` | `kubectl -n fleet-default get bundle <nom> -o yaml` → `status.conditions` |
| Bundle en `Modified` | une ressource a été modifiée hors Git (dérive) |
| Logs du contrôleur | `kubectl --context k3d-fleet-mgmt -n cattle-fleet-system logs deploy/fleet-controller` |

## 7. Et avec Rancher ?

Rancher embarque exactement ce Fleet. La seule différence : l'enregistrement des clusters est fait pour vous
(chaque cluster importé dans Rancher reçoit un fleet-agent et apparaît dans `fleet-default`), et le menu
**Continuous Delivery** affiche graphiquement GitRepos, Bundles et clusters. Toute la logique ci-dessus reste identique.

## 8. Nettoyer

```bash
./scripts/99-nettoyer.sh
```

> Les versions et options de Fleet évoluent : en cas d'écart, la référence est https://fleet.rancher.io
