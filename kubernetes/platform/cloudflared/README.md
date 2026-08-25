# Cloudflare Tunnel compartido (`homelab`)

Conector **`cloudflared`** de un **único túnel `homelab`** que expone por HTTPS los
servicios del clúster **sin abrir puertos** del router. Todos los proyectos usan este
mismo túnel; cada uno solo agrega sus **Public Hostnames** en el panel de Cloudflare.

## Requisitos

- Dominio gestionado por **Cloudflare** (p. ej. `nx73.app`; ver
  `protecso-pivas-doc/guides/mover-dominio-a-cloudflare.md`).
- Un **Tunnel** llamado **`homelab`** creado en Zero Trust → Networks → Tunnels
  (tipo *Cloudflared*); copiar su **token**.

## Instalación

```bash
kubectl apply -f namespace.yaml
# Crear el secret con el token real (NO versionar):
kubectl create secret generic cloudflared-token -n tunnel \
  --from-literal=token='<TUNNEL_TOKEN>'
kubectl apply -f cloudflared.yaml
```

## Agregar un proyecto al túnel

No se despliega otro conector. En el panel del túnel `homelab` → **Public Hostnames**,
añadir la ruta del proyecto al service interno del clúster:

| Ejemplo (hostname) | Service interno |
|--------------------|-----------------|
| `pivas.nx73.app` | `http://pivas-service.pivas.svc.cluster.local:4003` |
| `pivas-evidence.nx73.app` | `http://rustfs-service.storage.svc.cluster.local:9000` (exclusivo de PIVAS) |
| `pulse.nx73.app` | `http://pulse-service.pulse.svc.cluster.local:4002` |

Cloudflare crea automáticamente los registros DNS (CNAME) de esos subdominios.

## Notas

- El secret `cloudflared-token` **no se versiona** (solo la plantilla `*.example.yaml`).
- `cloudflared` es un cliente **saliente**: no necesita IP pública ni puertos abiertos.
- Alternativa declarativa (no usada aquí): túnel *locally-managed* con `config.yaml`
  en un ConfigMap para versionar las rutas en git; requiere el archivo de
  credenciales del túnel en vez del token.
