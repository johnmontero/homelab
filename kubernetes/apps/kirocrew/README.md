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
| `httproute.yaml` | HTTPRoute `crew.home.lab` → Service :5476 vía `homelab-gateway` (requiere bind + token) |
| `rbac.yaml` | SA `kirocrew-deployer` + Role/RoleBinding para CI→rollout de PIVAS (ns `pivas`) |
| `login-shim-configmap.yaml` | Script del sidecar de auto-login (mintea token y redirige) |
| `login-shim-service.yaml` | Service `kirocrew-login` :8088 (mismo pod, puerto del sidecar) |
| `login-shim-httproute.yaml` | HTTPRoute `crew-login.home.lab` → shim :8088 |
| `login-shim-secret.example.yaml` | Plantilla del Secret `kirocrew-login-auth` (basic-auth del shim) |

## Orden de aplicación

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f rbac.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml     # opcional (ver nota de acceso)
kubectl apply -f httproute.yaml   # opcional — expone crew.home.lab (ver "Acceso")
# Auto-login (opcional; ver "Auto-login"):
kubectl apply -f login-shim-configmap.yaml
kubectl apply -f login-shim-service.yaml
kubectl apply -f login-shim-httproute.yaml
# y el password del shim (NO versionado):
kubectl -n kirocrew create secret generic kirocrew-login-auth --from-literal=password='TU_PASSWORD'
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

### Acceso por el Gateway (crew.home.lab)

La imagen ya arranca con `KIROCREW_BIND=0.0.0.0` (escucha en red, no solo loopback),
así que el pod es alcanzable por su podIP. El bloqueo real es la **allowlist de Host**
del dashboard: rechaza cualquier `Host` que no sirva con `403 Host header not allowed`
(defensa anti DNS-rebinding). Por defecto solo permite `localhost`/`127.0.0.1`, por eso
el port-forward funciona pero `crew.home.lab` no.

Para permitir `crew.home.lab` hay que añadirlo a esa allowlist. Crew la deriva de sus
*allowed origins*, que se pueden ampliar con la env `KIROCREW_CORS_ORIGINS` (lista
separada por comas). El Deployment ya la incluye:

```yaml
env:
  - name: KIROCREW_CORS_ORIGINS
    value: "http://crew.home.lab"
```

Pasos:

1. Aplicar el Deployment (ya trae la env), el `Service` y el `HTTPRoute`:
   ```bash
   kubectl apply -f deployment.yaml
   kubectl apply -f service.yaml
   kubectl apply -f httproute.yaml
   ```
2. Crear el DNS rewrite en AdGuard: `crew.home.lab → 192.168.18.220` (IP del Gateway).

Verificar el enrutado:
```bash
kubectl -n kirocrew get httproute kirocrew-route -o wide
# desde la LAN, contra la IP del gateway. La raíz sirve el SPA (200) sin token,
# pero /api/* está protegido (403 sin token) — ver "Autenticación":
curl -H 'Host: crew.home.lab' http://192.168.18.220/
```

### Autenticación (token)

Crew **no tiene login usuario/contraseña**: el acceso es por **token**. La raíz (`/`)
carga el SPA sin auth, pero toda la funcionalidad (`/api/*`, WebSocket) exige el token;
sin él responde `403`.

1. Genera un token con el CLI (dentro del pod). TTL por defecto 20h (`--ttl` para
   cambiarlo, p. ej. `--ttl 12h`):
   ```bash
   kubectl -n kirocrew exec -it deploy/kirocrew -- kirocrew token
   ```
   Imprime una URL tipo `http://localhost:5476?token=eyJ...`.
2. El token es independiente del host: cambia `localhost:5476` por `crew.home.lab` y
   ábrelo una vez en el navegador:
   ```
   http://crew.home.lab?token=eyJ...
   ```
   Crew canjea el token por cookies de sesión (incluida una de refresh con ~30 días),
   así que quedas logueado en ese navegador sin volver a pegar el token.
3. Para rotar/renovar, vuelve a ejecutar `kirocrew token`.

> **Seguridad:** el token/URL es un **secreto tipo bearer**: quien lo tenga entra
> durante su TTL — no lo compartas ni lo pegues en canales/logs. Además, publicar
> `crew.home.lab` en la LAN da acceso a un agente que puede ejecutar herramientas
> dentro del clúster (incluido el `rollout restart` de PIVAS vía su SA). El acceso va
> en **HTTP plano** por el Gateway (token y cookies viajan sin cifrar): limítalo a una
> LAN de confianza y, si no lo es, pon TLS/auth delante en el Gateway.

### Auto-login (opcional): sidecar `login-shim`

Para no tener que correr `kirocrew token` a mano, un **sidecar** en el mismo pod
automatiza el flujo con una **página de login propia** (identidad de Kiro Crew: tema
oscuro, acento violeta, fuente Space Grotesk, logo real de `/logo.png`). Al abrir su
URL: si el navegador ya trae la cookie de sesión, redirige (`303`) directo a la
interfaz; si no, muestra el formulario y, al validar las credenciales, mintea un token
por loopback (`/api/token/local`, con el secreto local del PVC) y hace `303` a
`http://crew.home.lab/?token=…`. Se expone en su **propio hostname**
`crew-login.home.lab` (para no pisar rutas del SPA).

Piezas: `login-shim-configmap.yaml` (script), sidecar en `deployment.yaml`,
`login-shim-service.yaml` (:8088) y `login-shim-httproute.yaml` (`crew-login.home.lab`).

> **⚠️ Seguridad — importante:** mintear un token **equivale a saltarse la barrera de
> auth de Crew**. Un `/login` abierto dejaría entrar a cualquiera en la LAN que alcance
> el Gateway. Por eso el shim tiene **tres modos**, según el Secret `kirocrew-login-auth`
> y la env `LOGIN_SHIM_ALLOW_OPEN`:
>
> - **form-auth** (recomendado): con el Secret puesto, la página pide usuario/contraseña
>   (usuario `crew` por defecto) y solo entonces mintea.
> - **abierto**: `LOGIN_SHIM_ALLOW_OPEN=true` **sin** password → mintea a cualquiera.
>   Úsalo solo en una LAN de plena confianza.
> - **desactivado** (por defecto): sin password y sin `ALLOW_OPEN`, el shim responde
>   `503`. No crea un endpoint abierto por accidente.

Puesta en marcha:

```bash
# 1) password del shim (NO se versiona; ver login-shim-secret.example.yaml)
kubectl -n kirocrew create secret generic kirocrew-login-auth --from-literal=password='TU_PASSWORD'
# 2) recursos del shim
kubectl apply -f login-shim-configmap.yaml -f login-shim-service.yaml -f login-shim-httproute.yaml
kubectl apply -f deployment.yaml     # agrega el sidecar (reinicia el pod)
# 3) DNS rewrite en AdGuard: crew-login.home.lab → 192.168.18.220
```

Uso: abre `http://crew-login.home.lab`, ingresa usuario/contraseña en la página y te
deja dentro del dashboard ya autenticado. La cookie de refresh (~30 días) hace que,
pasada la primera vez, ir directo a `http://crew.home.lab/` también funcione hasta que
expire.

#### Cambiar de cuenta (Builder ID / SSO) — `/account`

En la OSS de Crew el login SSO del dashboard está deshabilitado (stub "not available in
OSS"). Por eso el shim añade una página **`/account`** (detrás del mismo login) para
gestionar la cuenta de `kiro-cli`:

- Muestra la **cuenta activa** (`kiro-cli user whoami`).
- Permite elegir **Builder ID** (free) o **SSO / Identity Center** (pro, con *start URL*
  + región) y ejecuta el **device flow**: muestra el enlace + código de verificación,
  hace polling hasta confirmar y ofrece **Cancelar**.
- El login del shim es **único**: el acceso al panel y `/account` comparten la misma
  cookie de sesión, así que la contraseña se pide una sola vez. Hay enlaces "← Volver"
  entre pantallas.
- Al terminar, recuerda **reiniciar Crew** para aplicar:
  `kubectl -n kirocrew rollout restart deploy/kirocrew` (reinicio manual, sin RBAC extra).

Cómo funciona: el sidecar corre `kiro-cli login … --use-device-flow` y escribe la sesión
en el **PVC compartido** (por eso el sidecar monta `home` en **RW**). No usa `kubectl
exec` ni RBAC nuevo. Cambiar de cuenta **cierra la sesión actual** (identidad única por
instancia). El `start URL`/región se validan y se pasan como argv (sin shell).

> El login **pro** de kiro-cli exige un **TTY** (prompta Start URL/Región, aunque se
> pasen por flag; sin terminal la región queda vacía → *"invalid host label"*). Por eso
> el sidecar lo ejecuta bajo un **PTY** y auto-confirma con Enter los valores
> pre-llenados desde los flags. El SSO requiere que la *start URL* sea válida y
> alcanzable; si no, kiro-cli responde *"service error"*.

> El acceso a `/account` está protegido por el mismo login del shim (cookie de sesión
> firmada). Igual que el auto-login, va en HTTP plano por la LAN: mantenlo en red de
> confianza.

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
