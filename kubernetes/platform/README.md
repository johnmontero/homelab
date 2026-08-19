# Plataforma (instaladores)

Componentes de base del clúster. Se instalan con sus manifiestos/instaladores
oficiales y luego se aplican los manifiestos de config que viven aquí (la
observabilidad sí usa Helm). Versiones observadas en el clúster actual.

## Base

| Componente | Versión | Instalación |
|-----------|---------|-------------|
| **k3s** | v1.30.14+k3s2 | server en zimaboard; agents en los Jetson (ver `../../docs/06-jetson-nodes.md`) |
| **local-path-provisioner** | (incluido en k3s) | StorageClass `local-path` (default) |
| **MetalLB** | — | `kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml` → luego `metallb/` |
| **Envoy Gateway** | — | `kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.2.4/install.yaml` → luego `gateway/` |
| **CloudNativePG** | v1.30 | `kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.0.yaml` |
| **cert-manager** | v1.21.1 | requerido por el Barman Cloud Plugin (backups) |
| **Barman Cloud Plugin** | v0.14.0 | `kubectl apply -f https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.14.0/manifest.yaml` |
| **NVIDIA device plugin** | v0.14.0 | `nvidia-device-plugin/daemonset.yaml` (nodeSelector `hardware=jetson`) |
| **kube-prometheus-stack** | Helm (prometheus-community) | `helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring -f monitoring/values.yaml` |

> Ajustar las versiones/URLs a las realmente instaladas antes de reinstalar.

## Config incluida en este repo

- `metallb/` — `IPAddressPool` `homelab-pool` (`192.168.18.220-240`) + `L2Advertisement`.
- `gateway/` — `GatewayClass` `eg` (Envoy) + `Gateway` `homelab-gateway` (HTTP :80,
  IP `192.168.18.220` vía MetalLB). Las rutas HTTP viven junto a cada app
  (p. ej. `../ai-agents/httproute-ai.yaml`).
- `nvidia-device-plugin/daemonset.yaml` — expone `nvidia.com/gpu` en los Jetson.
- `monitoring/` — `values.yaml` de kube-prometheus-stack (plano de monitoreo en
  zimaboard, node-exporter en todos los nodos), `prometheusrule-homelab.yaml`
  (alertas propias), `httproute-grafana.yaml` (`grafana.home.lab`) y
  `dashboards/` (dashboards propios vía sidecar; `kubectl apply -k ... --server-side`).
  Detalle en [`../../docs/07-observabilidad.md`](../../docs/07-observabilidad.md).

## Orden de instalación (reinstalar desde cero)

```bash
# 1) k3s (server + agents) — ver docs/06-jetson-nodes.md para los Jetson
# 2) namespaces y labels
kubectl apply -f kubernetes/cluster/namespaces.yaml
bash    kubernetes/cluster/node-labels.sh
# 3) MetalLB (operador) + config
kubectl apply -f <metallb-native.yaml>
kubectl apply -f kubernetes/platform/metallb/
# 4) Envoy Gateway (operador) + GatewayClass/Gateway
kubectl apply -f <envoy-gateway install.yaml>
kubectl apply -f kubernetes/platform/gateway/
# 5) NVIDIA device plugin (Jetson)
kubectl apply -f kubernetes/platform/nvidia-device-plugin/daemonset.yaml
# 6) Observabilidad (Helm)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f kubernetes/platform/monitoring/values.yaml
kubectl apply -f kubernetes/platform/monitoring/prometheusrule-homelab.yaml
kubectl apply -f kubernetes/platform/monitoring/httproute-grafana.yaml
# 7) CloudNativePG (operador) → luego kubernetes/data/ (ver ../README.md)
# 8) RustFS → kubernetes/storage/  |  IA → kubernetes/ai-agents/
```
