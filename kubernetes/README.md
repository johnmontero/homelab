# Kubernetes (k3s) — Homelab

Configuración declarativa del clúster **k3s** del homelab. Todo lo versionado aquí
debe poder **recrearse o modificarse** aplicando estos manifiestos.

- Diseño del clúster (nodos, arquitectura, storage): [`../docs/04-kubernetes-cluster.md`](../docs/04-kubernetes-cluster.md)
- Nodos Jetson (host, k3s agent, GPU): [`../docs/06-jetson-nodes.md`](../docs/06-jetson-nodes.md)
- Plataforma de datos PostgreSQL (CNPG): [`../docs/05-postgres-cnpg.md`](../docs/05-postgres-cnpg.md)
- Observabilidad (Prometheus/Grafana/Alertmanager): [`../docs/07-observabilidad.md`](../docs/07-observabilidad.md)

## Estructura

```
kubernetes/
├── cluster/                  # básicos del clúster
│   ├── namespaces.yaml
│   └── node-labels.sh        # etiquetas de nodo (kubectl)
├── platform/                 # componentes base (+ instaladores en README)
│   ├── README.md             # versiones, URLs y orden de instalación
│   ├── metallb/              # IPAddressPool + L2Advertisement (192.168.18.220-240)
│   ├── gateway/              # GatewayClass (eg) + Gateway (homelab-gateway)
│   ├── nvidia-device-plugin/ # DaemonSet GPU (Jetson)
│   └── monitoring/           # kube-prometheus-stack (values, alertas, HTTPRoute Grafana)
├── storage/                  # RustFS (S3) — ns storage
│   ├── rustfs-secret.example.yaml
│   ├── rustfs-pvc.yaml
│   ├── rustfs-deployment.yaml
│   └── rustfs-service.yaml
├── ai-agents/                # Ollama, LocalAI, Kokoro-TTS — ns ai-agents
│   ├── ollama.yaml           # deploy + svc + pvc
│   ├── ollama-secret.example.yaml
│   ├── localai.yaml          # deploy + svc + pvc + configmap
│   ├── kokoro-tts.yaml       # deploy + svc
│   └── httproute-ai.yaml     # ai.home.lab → ollama-service
└── data/                     # PostgreSQL (CloudNativePG)
    ├── postgres-dev-cluster.yaml
    ├── postgres-prod-cluster.yaml
    └── backups/              # → RustFS (pendiente de habilitar)
```

## Componentes de plataforma

| Componente | Namespace | Estado | Instalación |
|-----------|-----------|--------|-------------|
| k3s | — | ✅ | server (zimaboard) + 3 agents (Jetson) — `docs/06` |
| MetalLB | `metallb-system` | ✅ | operador + `platform/metallb/` |
| Envoy Gateway | `envoy-gateway-system` | ✅ | operador + `platform/gateway/` |
| NVIDIA device plugin | `kube-system` | ✅ | `platform/nvidia-device-plugin/` |
| CloudNativePG | `cnpg-system` | ✅ | operador v1.30 |
| RustFS (S3) | `storage` | ✅ | `storage/` |
| IA (Ollama/LocalAI/Kokoro) | `ai-agents` | ✅ | `ai-agents/` (corren en zimaboard/CPU) |
| cert-manager + Barman plugin | `cert-manager`/`cnpg-system` | ✅ | v1.21.1 / v0.14.0 — backups PITR a RustFS |
| kube-prometheus-stack | `monitoring` | ✅ | Helm + `platform/monitoring/` (Prometheus/Grafana/Alertmanager) |

## Orden de aplicación (reinstalar desde cero)

Detalle e instaladores oficiales en [`platform/README.md`](./platform/README.md).

```bash
# 1) k3s (server + agents) — docs/06-jetson-nodes.md
# 2) básicos
kubectl apply -f kubernetes/cluster/namespaces.yaml
bash    kubernetes/cluster/node-labels.sh
# 3) plataforma (operadores + config)
kubectl apply -f kubernetes/platform/metallb/
kubectl apply -f kubernetes/platform/gateway/
kubectl apply -f kubernetes/platform/nvidia-device-plugin/
# 3b) observabilidad (Helm) — ver platform/README.md y docs/07-observabilidad.md
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f kubernetes/platform/monitoring/values.yaml
kubectl apply -f kubernetes/platform/monitoring/prometheusrule-homelab.yaml
kubectl apply -f kubernetes/platform/monitoring/httproute-grafana.yaml
# 4) storage (crear antes el secret rustfs-creds; ver *.example.yaml)
kubectl apply -f kubernetes/storage/
# 5) IA
kubectl apply -f kubernetes/ai-agents/
# 6) datos (operador CNPG ya instalado)
kubectl apply -f kubernetes/data/postgres-dev-cluster.yaml
kubectl apply -f kubernetes/data/postgres-prod-cluster.yaml
# 7) backups a RustFS (cuando se habiliten) — ver docs/05-postgres-cnpg.md
```

## Runbooks rápidos

- **Cambiar recursos/parámetros:** editar el YAML y `kubectl apply -f ...`.
- **Secrets:** no se versionan (ver `.gitignore`); usar los `*.example.yaml`.
- **PostgreSQL:** runbooks (recrear, upgrades, backups) en `../docs/05-postgres-cnpg.md`.
- **`local-path` no expande:** dimensionar PVC de entrada.
