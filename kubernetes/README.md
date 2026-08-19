# Kubernetes (k3s) — Homelab

Configuración declarativa del clúster **k3s** del homelab. Todo lo versionado aquí
debe poder **recrearse o modificarse** aplicando estos manifiestos.

- Diseño del clúster (nodos, arquitectura, storage): [`../docs/04-kubernetes-cluster.md`](../docs/04-kubernetes-cluster.md)
- Plataforma de datos PostgreSQL (CNPG): [`../docs/05-postgres-cnpg.md`](../docs/05-postgres-cnpg.md)

## Estructura

```
kubernetes/
├── README.md                 # este archivo (índice + orden de aplicación)
└── data/                     # namespace `data`: PostgreSQL (CloudNativePG)
    ├── postgres-dev-cluster.yaml    # dev (zimaboard/amd64, 1 instancia)
    ├── postgres-prod-cluster.yaml   # prod (jetson-4gb/arm64, QoS Guaranteed)
    └── backups/                     # backups continuos → RustFS (PENDIENTE)
        ├── 00-secret-rustfs.example.yaml
        ├── 10-objectstore-rustfs.yaml
        └── 20-scheduledbackup-prod.yaml
```

## Componentes de plataforma (instalados fuera de este repo)

| Componente | Namespace | Estado | Notas |
|-----------|-----------|--------|-------|
| k3s | — | ✅ | 1 server (zimaboard) + 3 agents (Jetson) |
| CloudNativePG (operador) | `cnpg-system` | ✅ | v1.30 |
| RustFS (S3) | `storage` | ✅ | 1 réplica; `rustfs-service` :9000 |
| cert-manager | `cert-manager` | ⏳ pendiente | requerido por el plugin de backups |
| Barman Cloud Plugin | `cnpg-system` | ⏳ pendiente | backups a S3/RustFS |

## Orden de aplicación (recrear desde cero)

Requisito previo: el operador CNPG ya instalado (`cnpg-system`) y el namespace `data`.

```bash
# 0) namespace
kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -

# 1) clústeres PostgreSQL
kubectl apply -f kubernetes/data/postgres-dev-cluster.yaml
kubectl apply -f kubernetes/data/postgres-prod-cluster.yaml

# 2) backups (cuando se habiliten; ver docs/05-postgres-cnpg.md)
#   a. instalar cert-manager y el Barman Cloud Plugin
#   b. crear el secret rustfs-backup y el bucket pg-prod-backups en RustFS
#   c. aplicar el ObjectStore y el ScheduledBackup, y descomentar `spec.plugins`
#      en postgres-prod-cluster.yaml
kubectl apply -f kubernetes/data/backups/10-objectstore-rustfs.yaml
kubectl apply -f kubernetes/data/backups/20-scheduledbackup-prod.yaml
```

## Runbooks rápidos

- **Cambiar recursos/parámetros de una BD:** editar el YAML del cluster y
  `kubectl apply -f ...`. CNPG reconcilia (algunos parámetros requieren restart;
  `primaryUpdateMethod` por defecto es `restart`).
- **Recrear una BD desde cero (sin datos):** `kubectl delete cluster <nombre> -n data`
  y borrar su PVC (`kubectl delete pvc -n data -l cnpg.io/cluster=<nombre>`), luego
  `kubectl apply -f ...`. ⚠️ Destruye datos.
- **NO cambiar el major (17→18) editando `imageName` en caliente:** CNPG lo trata
  como *major upgrade* y puede quedarse atascado. Usar el procedimiento de upgrade
  de CNPG o recrear si no hay datos.
- **`local-path` no expande:** dimensiona el PVC de entrada; para crecer, hay que
  recrear/migrar.
