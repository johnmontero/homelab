# PostgreSQL en Kubernetes (CloudNativePG)

Plataforma de datos del homelab con **CloudNativePG** (operador en `cnpg-system`),
bajo el enfoque de **aislamiento total**: dos clústeres independientes en el
namespace `data`.

Manifiestos: [`../kubernetes/data/`](../kubernetes/data/).

## Diseño

| | `postgres-dev` | `postgres-prod` |
|---|---|---|
| Nodo | zimaboard (amd64, 16 GB) | jetson-4gb-01 (arm64) |
| Instancias | 1 | 1 (→ HA con Mac Mini) |
| QoS | Burstable | **Guaranteed** (requests==limits) |
| Storage | 10Gi local-path | 20Gi local-path |
| BD / owner | `dev_db` / `dev_admin` | `app_db` / `app_admin` |
| Backups | ❌ | ⏳ RustFS (PITR) — pendiente |
| PDB | off (1 instancia) | — |

- **Imagen:** `ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie` (multi-arch;
  **incluye pgvector** — verificado `/usr/share/postgresql/18/extension/vector.control`).
- **Extensiones habilitadas al bootstrap:** `uuid-ossp`, `vector` (pgvector).
- `enableSuperuserAccess: false`; TLS on. La app usa el usuario `owner` del initdb.
- Credenciales de la app: secret autogenerado `postgres-<cluster>-app` en `data`.

## Estado actual

- ✅ `postgres-dev` sano en `zimaboard2`.
- ✅ `postgres-prod` sano en `jetson-4gb-01`.
- ⏳ Backups continuos a RustFS: **pendientes** (falta cert-manager + plugin).

## Operación (runbooks)

### Conectarse / verificar
```bash
kubectl get cluster -n data
kubectl exec -n data postgres-prod-1 -c postgres -- \
  psql -d app_db -tAc "select extname||' '||extversion from pg_extension order by 1;"
```

### Cambiar recursos o parámetros
Editar el YAML del cluster (`kubernetes/data/postgres-*-cluster.yaml`) y aplicar:
```bash
kubectl apply -f kubernetes/data/postgres-prod-cluster.yaml
```
Algunos parámetros requieren restart (CNPG usa `primaryUpdateMethod: restart`).

### Recrear una BD (sin datos)
```bash
kubectl delete cluster postgres-dev -n data
kubectl delete pvc -n data -l cnpg.io/cluster=postgres-dev   # ⚠️ destruye datos
kubectl apply -f kubernetes/data/postgres-dev-cluster.yaml
```

### ⚠️ Upgrades de versión mayor
No cambiar `imageName` de PG17→PG18 en caliente: CNPG entra al reconciler de
*major upgrade* y, sin primario, se atasca (`no primary PVC found`). Usar el
procedimiento de upgrade de CNPG o, si no hay datos, recrear.

## Backups continuos a RustFS (pendiente de habilitar)

Objetivo: WAL archiving continuo + backup base diario → **RustFS (S3)**, para PITR.

**Requisitos e instalación (una vez):**
```bash
# 1) cert-manager (dependencia del plugin)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook

# 2) Barman Cloud Plugin
kubectl apply -f https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.14.0/manifest.yaml

# 3) bucket en RustFS (vía consola :9001 o mc): pg-prod-backups

# 4) secret con credenciales de RustFS en el namespace data
AK=$(kubectl get secret rustfs-creds -n storage -o jsonpath='{.data.RUSTFS_ACCESS_KEY}' | base64 -d)
SK=$(kubectl get secret rustfs-creds -n storage -o jsonpath='{.data.RUSTFS_SECRET_KEY}' | base64 -d)
kubectl create secret generic rustfs-backup -n data \
  --from-literal=ACCESS_KEY_ID="$AK" --from-literal=ACCESS_SECRET_KEY="$SK"

# 5) ObjectStore + ScheduledBackup
kubectl apply -f kubernetes/data/backups/10-objectstore-rustfs.yaml
kubectl apply -f kubernetes/data/backups/20-scheduledbackup-prod.yaml

# 6) habilitar el WAL archiver en postgres-prod: descomentar `spec.plugins`
#    en kubernetes/data/postgres-prod-cluster.yaml y aplicar.
```

**Backup manual / verificación:**
```bash
kubectl cnpg backup postgres-prod -n data     # requiere el plugin kubectl-cnpg
kubectl get backups.postgresql.cnpg.io -n data
```

> ⚠️ **RustFS es SPOF** (1 réplica sobre local-path, mismo hardware). Es PITR /
> anti-error lógico, **no DR**. Para DR real: copia periódica off-site (p. ej.
> `rclone` del bucket a otro destino / S3 en la nube).

## Roadmap

- **HA real:** al unir la **Mac Mini M1** (arm64, 500 GB) como nodo Linux, migrar
  el primario de `postgres-prod` allí y subir a `instances: 2+` con réplica en el
  Jetson 4 GB (misma arquitectura). Failover automático.
- **Migración a AWS:** CNPG corre igual en EKS; los backups a S3-compatible apuntan
  a **AWS S3** cambiando endpoint/credenciales. Migración a **RDS/Aurora** vía
  `pg_dump/restore` o replicación lógica. El diseño actual es "AWS-ready".
