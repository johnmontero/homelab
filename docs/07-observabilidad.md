# Observabilidad (Prometheus + Grafana + Alertmanager)

Stack **kube-prometheus-stack** (Prometheus Operator) para métricas, dashboards y
alertas. Instalado con Helm; valores versionados en
[`../kubernetes/platform/monitoring/values.yaml`](../kubernetes/platform/monitoring/values.yaml).

## Diseño

- **Namespace:** `monitoring`.
- **Plano de monitoreo fijado al ZimaBoard** (amd64, 16 GB): Prometheus, Grafana,
  Alertmanager, kube-state-metrics y el operador (`nodeSelector: zimaboard2`).
- **node-exporter** en **todos** los nodos (arm64 + amd64).
- **Prometheus** descubre PodMonitor/ServiceMonitor/PrometheusRule de **cualquier
  namespace** (`*SelectorNilUsesHelmValues: false`), así toma las métricas de CNPG.
- Retención 7d; PVC `local-path` (Prometheus 8Gi, Grafana 2Gi, Alertmanager 2Gi)
  sobre el ZimaBoard.

## Instalación / actualización

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f kubernetes/platform/monitoring/values.yaml
# Reglas de alerta propias:
kubectl apply -f kubernetes/platform/monitoring/prometheusrule-homelab.yaml
# Exponer Grafana:
kubectl apply -f kubernetes/platform/monitoring/httproute-grafana.yaml
```

## Métricas de PostgreSQL (CNPG)

Cada cluster CNPG tiene `spec.monitoring.enablePodMonitor: true` → crea un
`PodMonitor` en `data` que Prometheus scrapea (verificado: `cnpg_collector_up=1`
para `postgres-dev` y `postgres-prod`).

## Dashboards

El stack ya provisiona dashboards de Kubernetes y node-exporter. Los dashboards
propios se cargan vía el **sidecar** de Grafana (`grafana-sc-dashboard`), que
descubre ConfigMaps con la etiqueta `grafana_dashboard=1` en cualquier namespace.

- **CloudNativePG** (uid `cloudnative-pg`): dashboard oficial, versionado en
  [`../kubernetes/platform/monitoring/dashboards/cloudnativepg.json`](../kubernetes/platform/monitoring/dashboards/cloudnativepg.json).
  Se genera el ConfigMap con kustomize:
  ```bash
  kubectl apply -k kubernetes/platform/monitoring/dashboards/ --server-side
  ```
  > `--server-side` es obligatorio: el JSON (~253 KB) supera los 256 KB con la
  > anotación `last-applied` que añade el apply cliente.

Para agregar más dashboards: dejar el `.json` en `dashboards/` y añadirlo a
`files:` del `kustomization.yaml`.

## Acceso a Grafana

- URL: **http://grafana.home.lab** (requiere DNS rewrite en AdGuard:
  `grafana.home.lab → 192.168.18.220`). Alternativa sin DNS:
  `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80`.
- Usuario `admin`; contraseña autogenerada:
  ```bash
  kubectl -n monitoring get secret monitoring-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d; echo
  ```
  > Cambiarla tras el primer acceso (Grafana → perfil → cambiar contraseña).

## Alertas propias (`prometheusrule-homelab.yaml`)

| Alerta | Severidad | Condición |
|--------|-----------|-----------|
| `HomelabPVCAlmostFull` | critical | PVC <15% libre 15m (local-path **no** expande) |
| `HomelabNodeMemoryHigh` | warning | RAM de nodo >90% 10m (crítico en Jetson 2 GB) |
| `HomelabPodOOMKilled` | warning | contenedor terminado por OOM |
| `CNPGInstanceDown` | critical | `cnpg_collector_up == 0` 5m |

> Alertmanager está instalado pero **sin receptores** (no envía a ningún lado aún).
> Configurar un receptor (correo/Telegram/Slack) editando el `Alertmanager`/valores
> cuando se quiera notificación activa.
