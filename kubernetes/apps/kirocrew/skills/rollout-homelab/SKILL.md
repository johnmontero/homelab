---
name: rollout-homelab
description: Reinicia (rollout restart) cualquier Deployment del homelab (k3s) vía la API de Kubernetes con el token del ServiceAccount montado, sin kubectl. Genérico para todo deploy en el homelab (PIVAS, Pulse, etc.). Úsalo cuando el usuario diga "reinicia/rollout/redeploy <app>", "desplegar <app> en homelab", o tras confirmar que el CI de una app pasó a success y hay que recoger la imagen nueva.
triggers: rollout homelab, reinicia deploy, redeploy homelab, reiniciar deployment, restart deploy homelab, desplegar en homelab, rollout pivas, rollout pulse, reinicia pivas, reinicia pulse
---
# rollout-homelab — reinicio de un deploy en el homelab

Reinicia un `Deployment` del k3s del homelab para recoger la imagen `:latest`
recién publicada por el CI. **Genérico**: sirve para cualquier app del homelab
(PIVAS, Pulse, …); el namespace y el deployment son parámetros. No usa
`kubectl` (no está en el contenedor): parcha la anotación `restartedAt` del
Deployment vía la **API de Kubernetes** con el token del ServiceAccount montado
en el pod de Kiro Crew.

## Cuándo usarlo
- El usuario pide explícitamente reiniciar/redeployar una app del homelab.
- Tras confirmar que el **CI de GitHub Actions del repo pasó a `success`** para
  el commit desplegado (la imagen `:latest` ya está en GHCR).

## Cómo ejecutarlo
El namespace y el deployment se pasan por variables de entorno; no hay default de
app (para no reiniciar la equivocada por descuido):

```bash
# PIVAS
ROLLOUT_NS=pivas ROLLOUT_DEPLOY=pivas python3 rollout.py
# Pulse
ROLLOUT_NS=pulse ROLLOUT_DEPLOY=pulse python3 rollout.py
```

Salida esperada: `OK: rollout restart <ns>/<deploy> -> HTTP 200 @ <timestamp>`.

## Requisitos y límites
- Solo funciona **dentro del pod de Kiro Crew** (usa el token del SA en
  `/var/run/secrets/kubernetes.io/serviceaccount`).
- El RBAC (`kubernetes/apps/kirocrew/rbac.yaml`) debe permitir `patch` de
  deployments en el **namespace destino**. Hoy están habilitados `pivas` y
  `pulse`; para otros hay que **ampliar el RBAC** primero, si no la API devuelve
  **403**. (Cotejo despliega en AWS, no en el homelab.)
- No compila ni hace push del código: eso vive en los repos (fuera del pod).
  Este skill cubre **solo** el reinicio del deploy tras un CI verde.

## Verificar el resultado
El propio PATCH devuelve 200 si el rollout se disparó. Para confirmar que el
nuevo pod quedó listo, el usuario puede revisar en su máquina:
`kubectl -n <ns> rollout status deploy/<deploy>`.
