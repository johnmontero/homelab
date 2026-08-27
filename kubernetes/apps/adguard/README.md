# AdGuard — proxy de la UI por el Gateway (adguard.home.lab)

AdGuard Home corre **nativo en el host ZimaBoard** (app de ZimaOS), no en el clúster.
Su panel escucha en `10.0.1.1:3001`. Estos manifiestos lo exponen por el **Envoy
Gateway** en `http://adguard.home.lab` (sin puerto), para no tener que recordar `:3001`.

## Qué incluye

| Archivo | Rol |
|---------|-----|
| `namespace.yaml` | Namespace `adguard` |
| `backend.yaml` | `Service` sin selector + `EndpointSlice` manual → `10.0.1.1:3001` |
| `httproute.yaml` | HTTPRoute `adguard.home.lab` → Service `adguard:3001` vía `homelab-gateway` |

## Cómo funciona

AdGuard vive **fuera** del clúster, así que no hay pod ni selector que apunte a él. El
patrón estándar de Gateway API para destinos externos es:

1. un `Service` **sin selector** (k8s no le genera Endpoints por su cuenta), y
2. un `EndpointSlice` **manual** (`kubernetes.io/service-name: adguard`) con la
   IP:puerto reales del host.

Envoy Gateway lee ese `EndpointSlice` y enruta hacia `10.0.1.1:3001`.

## Aplicación

```bash
kubectl apply -f namespace.yaml
kubectl apply -f backend.yaml
kubectl apply -f httproute.yaml
```

DNS rewrite en AdGuard (Filters → DNS rewrites): `adguard.home.lab → 192.168.18.220`
(la IP del Gateway, **no** `10.0.1.1`).

## Verificación

```bash
# route aceptado por el gateway
kubectl -n adguard get httproute adguard-route -o wide

# por el gateway con Host (debe dar 302 → /login, no 404):
curl -H 'Host: adguard.home.lab' http://192.168.18.220/ -o /dev/null -w '%{http_code}\n'

# ya con el DNS rewrite puesto:
# abre http://adguard.home.lab
```

## Notas

- **Endpoint estático:** al no haber selector, el `EndpointSlice` no se reconcilia
  solo. Si AdGuard cambia de IP/puerto, edítalo a mano en `backend.yaml` y reaplica.
- **IP del host:** se usa `10.0.1.1` (LAN, estática), no la WAN `192.168.18.113` (DHCP
  del router de casa, puede cambiar).
- **Seguridad:** el panel de AdGuard ya exige login propio; esto solo añade una ruta
  HTTP en la LAN hacia ese mismo login (sin auth extra en el Gateway). El tráfico va en
  claro por HTTP, igual que el acceso directo por `:3001`.
- **Acceso directo:** sigue disponible `http://10.0.1.1:3001` (o `192.168.18.113:3001`)
  aunque no toques el DNS.
