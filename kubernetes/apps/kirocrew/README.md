# Kiro Crew — despliegue en k3s (homelab)

Manifiestos para correr **Kiro Crew** (workspace de agentes persistente: memoria,
skills, lecciones, jobs) en el homelab usando la imagen oficial multi-arch
`ghcr.io/kirodotdev/kirocrew:stable`.

> No es un camino documentado oficialmente para Kubernetes (la doc cubre `docker run`
> y "remote host + `kirocrew service install`"), pero la imagen Docker funciona como
> `Deployment`. Doc oficial: <https://kiro.dev/docs/crew/> y
> <https://github.com/kirodotdev/KiroCrew>.

## Qué incluye

| Archivo | Rol |
|---------|-----|
| `namespace.yaml` | Namespace `kirocrew` |
| `pvc.yaml` | PVC `kirocrew-home` (15Gi, `local-path`) → `/home/kirocrew` (TODO el estado) |
| `deployment.yaml` | Deployment 1 réplica, `Recreate`, fijado a nodo amd64, seccomp `Unconfined` |
| `service.yaml` | Service ClusterIP :5476 (solo útil con bind de red + token; ver abajo) |

## Orden de aplicación

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml   # opcional (ver nota de acceso)
```

## Primer arranque (login de kiro-cli)

Kiro Crew corre sobre `kiro-cli`, que necesita **sign-in por device-code** la primera
vez. Las credenciales quedan en el PVC (`/home/kirocrew`), así que sobreviven
reinicios.

1. Ver logs para el flujo inicial:
   ```bash
   kubectl -n kirocrew logs -f deploy/kirocrew
   ```
2. Completar el login (URL + código de device-code) desde el dashboard o por exec:
   ```bash
   kubectl -n kirocrew exec -it deploy/kirocrew -- kirocrew doctor
   ```
   Abre la URL que muestre y autoriza en tu navegador.

## Acceso al dashboard

Por defecto el dashboard **escucha en loopback** dentro del pod, así que el acceso
recomendado (y más seguro) es por port-forward — no expongas un dashboard sin auth
en la LAN:

```bash
kubectl -n kirocrew port-forward deploy/kirocrew 5476:5476
# abre http://localhost:5476
```

Para usar el `Service`/Gateway en su lugar, hay que habilitar **bind de red + auth por
token** en la config de Crew (Settings del dashboard). Solo entonces tiene sentido
agregar un `HTTPRoute` (Envoy Gateway `homelab-gateway`) o probes HTTP al Deployment.

## Caveat del sandbox (importante)

El agente prueba un sandbox con **user namespaces** (`unshare/clone`). Bajo containerd
(k3s), el perfil seccomp por defecto lo bloquea y **deshabilita la ejecución de
agentes**. Por eso el pod usa `securityContext.seccompProfile: Unconfined`.

Si tras el arranque los agentes siguen deshabilitados:
- Verifica con `kubectl -n kirocrew exec -it deploy/kirocrew -- kirocrew doctor`.
- Alternativa: bajar el nivel de sandbox en la config (`agent.sandbox`), asumiendo
  menos aislamiento. Es un trade-off de seguridad: le das a un agente acceso real a
  herramientas dentro del cluster.

## CI → rollout de PIVAS (RBAC en `rbac.yaml`)

Para que Crew dispare `kubectl rollout restart deploy/pivas` cuando el CI pase a
`success`, `rbac.yaml` crea un acceso a la API de k8s **acotado al ns `pivas`** (no
usa el kubeconfig de admin):

- `ServiceAccount` `kirocrew-deployer` (ns `kirocrew`).
- `Role` `pivas-rollout` (ns `pivas`): `patch`/`get`/`list`/`watch` de deployments +
  lectura de replicasets/pods (para `rollout status`).
- `RoleBinding` que une el Role al SA.

El Deployment ya referencia `serviceAccountName: kirocrew-deployer`, así que el token
se auto-monta en el pod. Aplícalo:

```bash
kubectl apply -f rbac.yaml
```

**Comando que ejecuta el agente** (usa el token auto-montado del SA; no requiere
kubeconfig):

```bash
kubectl \
  --server=https://kubernetes.default.svc \
  --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  --token="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  -n pivas rollout restart deploy/pivas
```

> **Requiere `kubectl` en el contenedor de Crew.** La imagen base puede no traerlo; si
> falta, instálalo en el pod o llama a la API de k8s por HTTP con el mismo token. Lo
> validas con:
> `kubectl -n kirocrew exec -it deploy/kirocrew -- sh -c 'command -v kubectl || echo NO-kubectl'`

**Verificar los permisos** (deben dar `yes` los dos primeros y `no` el tercero):

```bash
kubectl -n kirocrew exec -it deploy/kirocrew -- \
  kubectl auth can-i patch deploy/pivas -n pivas \
  --as=system:serviceaccount:kirocrew:kirocrew-deployer
```

### Endurecer más (opcional)
`list`/`watch` no aceptan `resourceNames`, pero `get`/`patch` sí. Si quieres limitar a
**solo** el deployment `pivas`, separa una regla con
`resourceNames: ["pivas"]` para `get`/`patch` y deja `list`/`watch` sin nombre.

## Notas de seguridad

- Dashboard **loopback** por defecto; remoto exige token. No lo publiques por
  Cloudflare/Ingress sin auth.
- Crew trae *deny patterns* y aprobaciones de herramientas; revisa acciones de alto
  impacto (deploys) y no pegues secretos en el chat.
- **Telemetría**: como `KIROCREW_HOME` no es `~/.kiro/crew`, el heartbeat anónimo se
  desactiva solo en este pod.

## Notas de operación

- **Estado**: todo en el PVC `kirocrew-home`. Si lo borras, pierdes memoria, skills,
  lecciones y el login. Respáldalo si te importa.
- **Arquitectura**: fijado a amd64 (ZimaBoard) por `local-path` (node-local). La
  imagen es multi-arch por si luego cambias de nodo/almacenamiento.
- **Recursos**: requests 250m/512Mi, limits 2 CPU/2Gi (embeddings + sesiones pueden
  pesar; ajusta según el nodo).
