# Acceso remoto con Tailscale (subnet-router)

Objetivo: alcanzar los equipos del lab (`10.0.1.0/24`) desde fuera de casa, sin
abrir puertos ni depender del doble NAT.

> **Por qué Tailscale y no el ZeroTier existente:** la red ZeroTier del ZimaBoard
> es **`IceWhale-RemoteAccess`** (gestionada por el fabricante de ZimaOS); no
> tienes admin del controlador, así que no puedes publicar la ruta `10.0.1.0/24`
> ahí. Con Tailscale controlas tú la consola. Conviven sin problema.

## 1. Instalar Tailscale en el ZimaBoard
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```
> Si falla por `/usr` de solo lectura (ZimaOS inmutable), usar la variante en
> **Docker**: `tailscale/tailscale` con `--network host --cap-add=NET_ADMIN` y
> volumen `/var/lib/tailscale`.

## 2. Levantar como subnet-router
```bash
sudo tailscale up --advertise-routes=10.0.1.0/24 --accept-dns=false
```
- `--advertise-routes=10.0.1.0/24` → ofrece el lab a la tailnet.
- `--accept-dns=false` → no toca el DNS local (AdGuard sigue mandando).

Abrir la URL de autenticación que imprime y **autorizar el nodo**.

## 3. Aprobar la ruta en la consola (obligatorio)
En [login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines):
- Nodo **ZimaBoard2** → `···` → **Edit route settings** → activar `10.0.1.0/24`.
- (Recomendado en un servidor) **Disable key expiry** en ese nodo.

## 4. En el equipo remoto
Instalar Tailscale, misma tailnet. En Linux añadir `--accept-routes`. Probar:
```bash
ping 10.0.1.1       # ZimaBoard
ping 10.0.1.10      # Mac mini
```

## 5. Verificación en el ZimaBoard
```bash
tailscale status
tailscale ip -4
```

## Notas
- Tailscale monta sus propias reglas de forward + SNAT para las subnet-routes, así
  que **normalmente funciona sin tocar `homelab-nat`**. Si el equipo remoto no
  llega a `10.0.1.x`, añadir forward explícito `tailscale0 ↔ eth1`.
- El acceso remoto funciona **aunque falle el tráfico cliente↔cliente en la LAN**
  (ver troubleshooting), porque todo enruta vía el ZimaBoard, que alcanza a todos.
