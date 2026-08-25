# Pulse (Protecso Pulse) — deploy en k3s

App Phoenix de seguimiento de avance de proyectos. Replica la plantilla de PIVAS.

- **Imagen**: `ghcr.io/protecso-sac/pulse-fs:latest` (CI en el repo `protecso-pulse-fs`).
- **Nodo**: fijado a `amd64` (imagen de release amd64), como postgres-dev.
- **BD**: base `pulse` en el cluster CNPG `postgres-dev` (owner `dev_admin`).
- **Puerto**: 4002. **Externo**: `pulse.nx73.app` vía Cloudflare Tunnel `homelab`
  (`http://pulse-service.pulse.svc.cluster.local:4002`). Interno LAN: `pulse.home.lab`.

## Prerrequisitos imperativos (NO versionados)

El paquete GHCR `pulse-fs` es **privado** → se necesita un pull secret, igual que
PIVAS (adjunto al serviceAccount `default`):

```bash
# 1) Namespace
kubectl apply -f namespace.yaml

# 2) Pull secret GHCR (copiado del de PIVAS o creado con un PAT read:packages)
kubectl -n pivas get secret ghcr-creds -o json \
  | python3 -c "import sys,json;s=json.load(sys.stdin);[s['metadata'].pop(k,None) for k in ['namespace','resourceVersion','uid','creationTimestamp','ownerReferences','managedFields']];s['metadata']['namespace']='pulse';print(json.dumps(s))" \
  | kubectl apply -f -
kubectl -n pulse patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ghcr-creds"}]}'

# 3) Secret de entorno (ver pulse-secret.example.yaml; NO versionar el real)
DBPASS=$(kubectl -n data get secret postgres-dev-app -o jsonpath='{.data.password}' | base64 -d)
kubectl create secret generic pulse-env -n pulse \
  --from-literal=PHX_SERVER=true --from-literal=PHX_HOST=pulse.nx73.app \
  --from-literal=PORT=4002 --from-literal=SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  --from-literal=DB_HOST=postgres-dev-rw.data.svc.cluster.local --from-literal=DB_PORT=5432 \
  --from-literal=DB_USER=dev_admin --from-literal=DB_PASSWORD="$DBPASS" --from-literal=DB_NAME=pulse \
  --from-literal=S3_ENDPOINT=http://rustfs-service.storage.svc.cluster.local:9000 \
  --from-literal=S3_REGION=us-east-1 \
  --from-literal=S3_AVATARS_BUCKET=pulse-avatars --from-literal=S3_TOOLS_BUCKET=pulse-tools
```

## Aplicar

```bash
kubectl apply -f database.yaml   # crea la base pulse (CNPG Database CRD)
kubectl apply -f service.yaml -f deployment.yaml -f httproute.yaml
```

## Actualizar (nuevo release)

Push a `main` en `protecso-pulse-fs` → CI construye y publica `:latest` → luego:

```bash
kubectl -n pulse rollout restart deploy/pulse
```

## Notas

- El initContainer `migrate` corre `Pulse.Release.migrate()` antes de arrancar.
- Migración inicial de datos: se restauró un `pg_dump` de `pulse_dev` local en la
  base `pulse` (esquema + datos), por lo que `migrate` queda no-op.
- Storage: Pulse aún no tiene código de S3; las claves `S3_*` del secret quedan
  listas (RustFS) para cuando se implemente (avatares/tools).
