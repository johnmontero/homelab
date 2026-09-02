# Kuska — deploy en k3s

App Phoenix (fullstack SSR) — asistente multi-tenant (owner `protecso`). Replica la
plantilla de Pulse/PIVAS.

- **Imagen**: `ghcr.io/protecso-sac/kuska-fs:latest` (CI en el repo `protecso-kuska-fs`).
- **Nodo**: fijado a `amd64` (imagen de release amd64), como postgres-dev.
- **BD**: base `kuska` en el cluster CNPG `postgres-dev` (owner `dev_admin`).
- **Puerto**: 4003. **Externo**: `kuska.nx73.app` (Cloudflare Tunnel — pendiente).
  Interno LAN: `kuska.home.lab`.
- **Libs**: usa `protecso_ui`, `tenancy`, `notifier`, `agent_core`, `acervo` (git deps
  en :prod, pineadas por `mix.lock`).
- **LLM**: Amazon Bedrock **opcional** (envs `BEDROCK_*`; sin ellas la app arranca igual).
- Sin S3 por ahora (a diferencia de Pulse).

## Prerrequisitos imperativos (NO versionados)

El paquete GHCR `kuska-fs` es **privado** → se necesita un pull secret, igual que
PIVAS/Pulse (adjunto al serviceAccount `default`):

```bash
# 1) Namespace
kubectl apply -f namespace.yaml

# 2) Pull secret GHCR (copiado del de PIVAS)
kubectl -n pivas get secret ghcr-creds -o json \
  | python3 -c "import sys,json;s=json.load(sys.stdin);[s['metadata'].pop(k,None) for k in ['namespace','resourceVersion','uid','creationTimestamp','ownerReferences','managedFields']];s['metadata']['namespace']='kuska';print(json.dumps(s))" \
  | kubectl apply -f -
kubectl -n kuska patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr-creds"}]}'

# 3) Secret de entorno (ver kuska-secret.example.yaml; NO versionar el real)
DBPASS=$(kubectl -n data get secret postgres-dev-app -o jsonpath='{.data.password}' | base64 -d)
kubectl create secret generic kuska-env -n kuska \
  --from-literal=PHX_SERVER=true --from-literal=PHX_HOST=kuska.nx73.app \
  --from-literal=PORT=4003 --from-literal=SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  --from-literal=DB_HOST=postgres-dev-rw.data.svc.cluster.local --from-literal=DB_PORT=5432 \
  --from-literal=DB_USER=dev_admin --from-literal=DB_PASSWORD="$DBPASS" --from-literal=DB_NAME=kuska
```

## Aplicar

```bash
kubectl apply -f database.yaml   # crea la base kuska (CNPG Database CRD)
kubectl apply -f service.yaml -f deployment.yaml -f httproute.yaml
kubectl -n kuska rollout status deploy/kuska --timeout=180s
```

## Actualizar (nuevo release)

Push a `main` en `protecso-kuska-fs` → CI construye y publica `:latest` → luego, desde
Crew (RBAC ya cubre el ns `kuska`) o manual:

```bash
kubectl -n kirocrew exec deploy/kirocrew -- \
  env ROLLOUT_NS=kuska ROLLOUT_DEPLOY=kuska \
  python3 /home/kirocrew/.kiro/crew/skills/rollout-homelab/rollout.py
# o:
kubectl -n kuska rollout restart deploy/kuska
```

## Notas

- El initContainer `migrate` corre `Kuska.Release.migrate()` antes de arrancar. El
  directorio `priv/repo/migrations` está **vacío** por ahora → `migrate` es no-op
  (pero valida la conexión a la BD).
- `kuska.home.lab` requiere el DNS rewrite en AdGuard → `192.168.18.220` (IP del gateway).
- El acceso público (`kuska.nx73.app`) por Cloudflare Tunnel queda **pendiente**.
