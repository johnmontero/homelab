# PIVAS AI — despliegue en k3s (homelab)

Manifiestos para desplegar **PIVAS** (Phoenix) en el homelab. El ingreso externo se
hace por el **túnel Cloudflare compartido `homelab`** (conector en
`platform/cloudflared/`, no por proyecto): PIVAS solo aporta sus Public Hostnames. El
**video** usa **LiveKit Cloud** (Cloudflare Tunnel no transporta el media UDP de
WebRTC). Guía completa y contexto: `protecso-pivas-doc/guides/despliegue-homelab.md`
y ADR-0009.

## Depende de la plataforma ya instalada

- **Envoy Gateway** `homelab-gateway` (ns `default`, listener `http`).
- **CloudNativePG** cluster `postgres-dev` (ns `data`), rol `dev_admin`.
- **RustFS** `rustfs-service` (ns `storage`, puerto 9000), secret `rustfs-creds`.

## Prerrequisitos (fuera de estos manifiestos)

1. **Imagen de release** de `protecso-pivas-fs` (amd64) publicada en un registry
   accesible por el clúster. El `Dockerfile` está en `app/src/Dockerfile` y el helper
   `Pivas.Release.migrate/0` en `lib/pivas/release.ex`. El build necesita un token de
   GitHub (secreto BuildKit `github_token`) por las git deps privadas. Comando de
   build/push en `protecso-pivas-doc/guides/despliegue-homelab.md` (fase A). Ajustar
   `image:` en `deployment.yaml` y `bucket-init.job.yaml` si usas otro registry/tag.
2. **Proyecto LiveKit Cloud** (URL `wss://…livekit.cloud`, API key y secret).
3. **Túnel Cloudflare compartido `homelab`** ya instalado (ver
   `platform/cloudflared/`) y dominio `nx73.app` gestionado por Cloudflare. En el
   panel del túnel `homelab`, agregar los Public Hostnames de PIVAS:
   - `pivas.nx73.app` → `http://pivas-service.pivas.svc.cluster.local:4003`
   - `pivas-evidence.nx73.app` → `http://rustfs-service.storage.svc.cluster.local:9000`
     (subdominio **exclusivo de PIVAS**: solo el bucket `cdat-pivas-evidence-storage`;
     otros proyectos usan su propio subdominio/bucket)
   (Guía para mover el dominio: `protecso-pivas-doc/guides/mover-dominio-a-cloudflare.md`.)

## Orden de aplicación

```bash
# 1) Namespace
kubectl apply -f namespace.yaml

# 2) Base de datos 'pivas' en el cluster CNPG dev
kubectl apply -f database.yaml

# 3) Secrets (NO versionar los reales; ver *.example.yaml)
#    - pivas-env       (variables de la app; incluye DB/S3/LiveKit)
#    - cloudflared-token (token del túnel)
#    Crear con kubectl create secret ... (ver comentarios en los *.example.yaml)

# 4) Bucket de evidencia + CORS en RustFS (idempotente)
kubectl apply -f bucket-init.job.yaml

# 5) App: Deployment + Service
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 6) Ruta interna opcional (health-check en LAN)
kubectl apply -f httproute.yaml
```

> El ingreso externo NO se despliega aquí: usa el túnel compartido `homelab`
> (`platform/cloudflared/`). Solo hay que **agregar los Public Hostnames** de PIVAS
> (`pivas.` y `pivas-evidence.nx73.app`) en el panel del túnel.

## Verificación

- Interno (LAN): `curl -H 'Host: pivas.home.lab' http://192.168.18.221/` → 200/302.
- Externo (celular): abrir `https://pivas.nx73.app`, generar enlace de captura y
  probar cámara/subida de fotos. El video va por LiveKit Cloud; las fotos a
  `https://pivas-evidence.nx73.app` (RustFS).

## Notas

- **Secrets** (`pivas-env`, `cloudflared-token`) **no se versionan** (política del
  repo). Solo se versionan las plantillas `*.example.yaml`.
- **Arquitectura**: los pods se fijan al nodo **amd64** (ZimaBoard); la imagen debe
  ser amd64 (o multi-arch).
- **check_origin** de Phoenix (:prod) valida contra `PHX_HOST=pivas.nx73.app`; por eso
  el LiveView se prueba por el dominio público, no por `pivas.home.lab`.
- **Cloudflare Free**: límite de ~100 MB por request (las fotos ~200–500 KB pasan sin
  problema). Desactivar cache en `pivas-evidence.nx73.app`.
