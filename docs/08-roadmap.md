# Roadmap / Pendientes del Homelab

Mejoras identificadas y **aún no implementadas**. Ordenadas por prioridad. Se
documentan aquí para retomarlas más adelante.

## Observabilidad

### Prioridad alta

- **Receptor en Alertmanager.** Hoy las alertas (`CNPGInstanceDown`,
  `HomelabPVCAlmostFull`, `HomelabNodeMemoryHigh`, `HomelabPodOOMKilled`) se
  **evalúan pero no notifican**. Configurar un receptor (Telegram / Slack / correo)
  y, si es email, el `SMTP`. Se edita en los valores del Alertmanager del
  kube-prometheus-stack.
- **Logs centralizados (Loki + Alloy/Promtail).** Solo hay métricas. Loki permite
  ver logs de pods/nodos para depurar (p. ej. por qué crasheó un contenedor).
  Complemento natural de Prometheus; se integra en Grafana como datasource.

### Prioridad media

- **Monitoreo de disponibilidad (blackbox-exporter).** No hay probes HTTP: no se
  sabe si `grafana.home.lab`, `ai.home.lab` o RustFS responden. Con
  `prometheus-blackbox-exporter` + `Probe`/targets se obtienen alertas de
  "servicio caído".
- **HTTPS/TLS en Grafana.** Hoy es HTTP plano. `cert-manager` ya está instalado
  (se puso para backups); emitir un cert (CA interna) para `grafana.home.lab` y
  servir por HTTPS en el Gateway.
- **Contraseña admin de Grafana.** Sigue con la autogenerada del chart. Cambiarla
  y, si se quiere, definir usuarios/OAuth.

### Prioridad baja / límites conocidos

- **Retención e histórico.** Prometheus a 7d sobre PVC `local-path` 8Gi (no
  expande). Para histórico largo: dimensionar mejor el PVC de entrada o usar
  remote-write. OK para el tamaño actual.
- **Métricas de GPU (Jetson) y RustFS.** Detallado en
  [`07-observabilidad.md`](./07-observabilidad.md) (sección roadmap): requieren
  `jetson-stats`/jtop + exporter (GPU) y un endpoint `/metrics` en RustFS.

## Red / Acceso

- **Tailscale subnet-router (`10.0.1.0/24`).** Quedó en curso. Da acceso remoto
  real y, de paso, permitiría alcanzar los Jetson desde la MacBook.
- **Topología L2 MacBook ↔ Jetson.** Hoy la MacBook (`10.0.1.11`) no alcanza los
  Jetson (`10.0.1.20-22`): resuelven por DNS pero no hay ruta L2 (cuelgan del
  segmento del ZimaBoard). Resolver con mismo switch, ruteo por el ZimaBoard o
  Tailscale. Ver [`06-jetson-nodes.md`](./06-jetson-nodes.md).

## Datos / Backups

- **Offsite backup mirror.** El CronJob `offsite-backup-mirror` (mc mirror
  RustFS → S3 externo) está **suspendido** esperando el secret `offsite-backup`
  (destino S3 externo). Sin él, los backups PITR de `postgres-prod` viven solo en
  RustFS (mismo homelab). Ver [`05-postgres-cnpg.md`](./05-postgres-cnpg.md).

## Orden sugerido

1. Receptor de Alertmanager (rápido, alto valor).
2. Loki + Alloy (logs) — mayor salto de capacidad.
3. blackbox-exporter (uptime de servicios).
4. TLS en Grafana / offsite backup / Tailscale, según urgencia.
