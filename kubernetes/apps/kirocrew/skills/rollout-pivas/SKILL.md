---
name: rollout-pivas
description: Reinicia el Deployment de PIVAS en el homelab (k3s) haciendo un rollout restart vía la API de Kubernetes con el token del ServiceAccount montado. Úsalo cuando el usuario diga "reinicia pivas", "rollout pivas", "redeploy pivas", "reinicia el deploy de pivas" o tras confirmar que el CI de PIVAS pasó a success y hay que recoger la imagen nueva.
triggers: reinicia pivas, rollout pivas, redeploy pivas, reiniciar deploy pivas, restart pivas, desplegar pivas homelab
---
# rollout-pivas — reinicio del deploy de PIVAS

Reinicia `deploy/pivas` (ns `pivas`) en el k3s del homelab para recoger la
imagen `:latest` recién publicada por el CI. No usa `kubectl` (no está en el
contenedor): parcha la anotación `restartedAt` del Deployment vía la **API de
Kubernetes** con el token del ServiceAccount `kirocrew-deployer` montado en el
pod.

## Cuándo usarlo
- El usuario pide explícitamente reiniciar/redeployar PIVAS.
- Tras confirmar que el **CI de GitHub Actions de `protecso-pivas-fs` pasó a
  `success`** para el commit desplegado (la imagen `:latest` ya está en GHCR).

## Cómo ejecutarlo
Corre el script incluido (ruta relativa a este skill):

```bash
python3 rollout.py
```

Salida esperada: `OK: rollout restart pivas/pivas -> HTTP 200 @ <timestamp>`.

Para otro deployment/namespace (mismo patrón, si el RBAC lo permite):

```bash
ROLLOUT_NS=<ns> ROLLOUT_DEPLOY=<deploy> python3 rollout.py
```

## Requisitos y límites
- Solo funciona **dentro del pod de Kiro Crew** (usa el token del SA en
  `/var/run/secrets/kubernetes.io/serviceaccount`).
- El RBAC (`kubernetes/apps/kirocrew/rbac.yaml`) solo permite `patch` de
  deployments en el ns **`pivas`**. En otros namespaces la API devolverá 403.
- No compila ni hace push del código: eso vive en los repos (fuera del pod).
  Este skill cubre **solo** el reinicio del deploy tras un CI verde.

## Verificar el resultado
El propio PATCH devuelve 200 si el rollout se disparó. Para confirmar que el
nuevo pod quedó listo, el usuario puede revisar en su máquina:
`kubectl -n pivas rollout status deploy/pivas`.
