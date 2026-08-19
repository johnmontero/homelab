# Clúster Kubernetes (k3s)

Clúster **k3s** sobre la LAN del lab (`10.0.1.0/24`). 1 server (control-plane) +
3 agents. Es la base para servicios propios y el ensayo de apps productivas antes
de migrar algunas a AWS.

## Nodos

| Nodo | Rol | Arch | RAM | IP | Uso previsto |
|------|-----|------|-----|----|--------------|
| `zimaboard2` | control-plane, master | amd64 | 16 GB | 10.0.1.1 | apps generales, **postgres-dev** |
| `jetson-4gb-01` | worker | arm64 | 4 GB | 10.0.1.20 | **postgres-prod**, cargas arm64 |
| `jetson-2gb-01` | worker | arm64 | 2 GB | 10.0.1.21 | cargas ligeras / GPU (CUDA) |
| `jetson-2gb-02` | worker | arm64 | 2 GB | 10.0.1.22 | cargas ligeras / GPU (CUDA) |

## Restricciones clave (condicionan el diseño)

1. **Arquitectura mixta (3× arm64 + 1× amd64).** La replicación física de
   PostgreSQL (y por tanto el HA/failover de CNPG) exige **misma arquitectura**
   entre instancias. ⇒ Un clúster con réplicas debe ser **homogéneo**: el HA de
   `postgres-prod` vivirá **solo en arm64** (Jetson + futura Mac Mini M1). El
   zimaboard (amd64) solo puede alojar instancias **únicas** amd64.
2. **Storage = `local-path` (node-local).** No hay replicación de bloque ni
   `ReadWriteMany`. El PVC queda **anclado al nodo**; si el nodo cae, esa instancia
   espera a que vuelva (las réplicas conservan los datos). Además **no expande**:
   dimensionar los PVC de entrada.
3. **RAM ajustada** en los Jetson de 2 GB (~1 GB útil). El nodo fuerte es el
   zimaboard (amd64, no-arm64).

## Namespaces

| Namespace | Contenido |
|-----------|-----------|
| `data` | PostgreSQL (CloudNativePG): `postgres-dev`, `postgres-prod` |
| `cnpg-system` | Operador CloudNativePG (+ plugin de backups, pendiente) |
| `storage` | RustFS (S3-compatible) — destino de backups |
| `ai-agents` | Cargas de agentes/IA |
| `envoy-gateway-system`, `metallb-system` | Ingress/LoadBalancer |
| `cert-manager` | (pendiente) requerido por el plugin de backups |

## StorageClass

| Nombre | Provisioner | Reclaim | Binding | Expansión |
|--------|-------------|---------|---------|-----------|
| `local-path` (default) | `rancher.io/local-path` | Delete | WaitForFirstConsumer | ❌ |

## Roadmap de hardware

- **Mac Mini M1 (arm64, 500 GB):** puede unirse como nodo si corre **Linux**
  (Asahi Linux bare-metal recomendado, o VM Linux arm64). macOS no puede ser nodo.
  Al ser arm64 es **compatible con la replicación** de los Jetson → será el
  **primario de `postgres-prod`** (500 GB) con réplica en el Jetson 4 GB ⇒ HA.
  Nota: su GPU/NPU no sirve para IA en k8s (sin CUDA); para GPU quedan los Jetson.
- **Más zimaboards / mini-PC (amd64):** ampliar cómputo de apps; etiquetar por rol.
- **Control-plane HA:** hoy el master es único (SPOF del plano de control). Para
  "prod" serio, más adelante 3 servers.

## Convenciones

- Etiquetar nodos/cargas por rol (`homelab.tier: dev|prod`) y usar
  `nodeSelector`/afinidad para ubicar cada workload en el nodo correcto.
- Fijar imágenes a **tags inmutables** (no `latest`) y versionar los manifiestos
  en `kubernetes/`.
