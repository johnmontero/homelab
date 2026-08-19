# Router ZimaBoard 2 — WAN/LAN, NAT, DHCP/DNS y nombres

Configuración del ZimaBoard 2 como router de borde del lab. SO: **ZimaOS** (base
Debian) con **NetworkManager** gestionando las interfaces y **AdGuard Home** ya
instalado como DNS.

> Interfaces: `eth0` = WAN (al router de casa), `eth1` = LAN (al switch del lab).
> Verifica con `ip -br link` / `ip -br addr` antes de aplicar nada.

---

## 1. WAN (eth0)

- Toma IP por **DHCP** del router de casa (`192.168.18.113`).
- **Recomendado:** en el router de casa, crear una **reserva DHCP** por la MAC de
  `eth0` para que la IP WAN no cambie.
  ```bash
  cat /sys/class/net/eth0/address     # MAC de la WAN
  ```

## 2. LAN (eth1) — IP estática

Se configura desde la **UI de ZimaOS** (Red → eth1 → editar):

- Método: **Manual**
- IP: **`10.0.1.1`**  ·  Máscara: **`255.255.255.0`**
- **Puerta de enlace: vacía** (la default sale por eth0/WAN, no por eth1)
- DNS: vacío

Verificación:
```bash
ip -br addr show eth1      # debe mostrar SOLO 10.0.1.1/24
ip route | grep -E 'eth1|default'
# default solo via 192.168.18.1 dev eth0
# 10.0.1.0/24 dev eth1 ... src 10.0.1.1
```

> ⚠️ eth1 **no** debe estar en modo DHCP-cliente. Si aparece una segunda IP
> (`10.0.1.x` extra) o una ruta `default via 10.0.1.1 dev eth1`, es que quedó como
> cliente DHCP; ponla en Manual y limpia con `sudo ip addr del <ip> dev eth1`.

## 3. NAT (LAN → WAN)

El enrutamiento/NAT no lo hace AdGuard; se aplica con `iptables` y se persiste con
un servicio systemd. **Aditivo** (convive con Docker y libvirt, no usa
`flush ruleset`).

Como en ZimaOS `/usr/local/sbin` no existe (/usr de solo lectura), las reglas van
**embebidas en el propio servicio** (sin script externo):

`/etc/systemd/system/homelab-nat.service`
```ini
[Unit]
Description=Homelab NAT (eth1 -> eth0)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'sysctl -w net.ipv4.ip_forward=1'
ExecStart=/bin/sh -c 'iptables -t nat -C POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE'
ExecStart=/bin/sh -c 'iptables -C FORWARD -i eth1 -o eth0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i eth1 -o eth0 -j ACCEPT'
ExecStart=/bin/sh -c 'iptables -C FORWARD -i eth0 -o eth1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD -i eth0 -o eth1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT'

[Install]
WantedBy=multi-user.target
```

Activar y verificar:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-nat.service
systemctl is-active homelab-nat                     # active
sudo iptables -t nat -S POSTROUTING | grep 10.0.1   # regla MASQUERADE
```

## 4. DHCP + DNS (AdGuard Home)

ZimaOS ya trae **AdGuard Home** escuchando DNS en el puerto 53. En vez de montar
dnsmasq (choca en el 53 y AdGuard ya cubre DNS), se usa **el DHCP integrado de
AdGuard**.

> El `dnsmasq` que se ve corriendo es el de **libvirt** (solo sirve `virbr0` /
> `192.168.122.x`). **No tocar.**

### DHCP (AdGuard → Settings → DHCP settings)
- Interface: **`eth1`**
- Gateway: **`10.0.1.1`**  ·  Máscara: **`255.255.255.0`**
- Rango: **`10.0.1.100` – `10.0.1.200`**  ·  Lease: 12 h
- (Los clientes reciben DNS = `10.0.1.1` = AdGuard.)

### Reservas estáticas (por MAC)
Fuera del pool dinámico para orden (ej. `.10`, `.11`):

| MAC | IP | Host |
|-----|----|----|
| `14:98:77:7b:3d:6f` | `10.0.1.10` | `mac-mini` |
| `d8:eb:97:b8:78:1c` | `10.0.1.11` | `macbook-pro` |

### DNS local (`home.lab`)
- **Dominio local de DHCP**: por defecto AdGuard usa `lan`; cambiarlo a
  **`home.lab`** en Settings → DHCP (avanzado) para que los nombres resuelvan como
  `<equipo>.home.lab`.
- **DNS rewrites** (Filters → DNS rewrites) como respaldo fijo (van a la misma IP
  que la reserva):
  - `mac-mini.home.lab` → `10.0.1.10`
  - `macbook-pro.home.lab` → `10.0.1.11`

> **Regla de oro:** por equipo, la **reserva DHCP**, el **DNS rewrite** y la **IP
> real** deben ser la MISMA IP. Tras crear/editar reservas, **renueva DHCP** en el
> equipo (`sudo ipconfig set en0 DHCP` en macOS) para que tome la IP nueva.

## 5. Convención de nombres (macOS)

En cada Mac, fija los tres nombres al mismo label (sin espacios ni puntos):
```bash
sudo scutil --set ComputerName  "mac-mini"
sudo scutil --set LocalHostName "mac-mini"
sudo scutil --set HostName      "mac-mini"
```
Resultado: `mac-mini.local` (Bonjour) y `mac-mini.home.lab` (AdGuard).

| Equipo | Label |
|--------|-------|
| Mac mini M1 | `mac-mini` |
| MacBook Pro M4 | `macbook-pro` |
| Jetson | `jetson` |
| ZimaBoard | `zimaboard` |

## 6. SSH entre equipos

Activar **Remote Login** por la UI (por CLI exige *Full Disk Access*):
**Ajustes → General → Compartir → Inicio de sesión remoto → ON**.

```bash
ssh usuario@mac-mini.home.lab      # por DNS del lab
ssh usuario@mac-mini.local         # por Bonjour (mismo switch)
ssh usuario@10.0.1.10              # por IP
```

## 7. Prueba de reinicio (persistencia)

```bash
sudo reboot
# al volver:
systemctl is-active homelab-nat                     # active
sudo iptables -t nat -S POSTROUTING | grep 10.0.1   # MASQUERADE presente
# desde un cliente:
ping -c2 1.1.1.1 && ping -c2 google.com
```
Todo debe levantar solo: eth1 (NetworkManager), AdGuard (su servicio) y el NAT
(`homelab-nat.service`).
