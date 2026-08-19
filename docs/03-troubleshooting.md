# Solución de problemas (homelab)

Registro de problemas encontrados durante la instalación y su causa/solución.

## Red / router

### eth1 con dos IPs y ruta `default via 10.0.1.1 dev eth1`
- **Causa:** eth1 quedó en modo **DHCP-cliente** (tomó una lease además de la IP
  estática).
- **Solución:** poner eth1 en **Manual** (`10.0.1.1/24`, gateway vacío). Limpiar:
  `sudo ip addr del <ip-sobrante> dev eth1`.

### Internet no sale del lab
- Revisar `net.ipv4.ip_forward=1` y la regla `MASQUERADE` (`homelab-nat.service`).
- `sudo iptables -t nat -S POSTROUTING | grep 10.0.1`.

## dnsmasq / DNS

### Se abandonó dnsmasq propio; se usa AdGuard
- **Causa:** AdGuard Home ya ocupa el **puerto 53** (`*:53`). Montar dnsmasq para
  DNS choca. Además AdGuard trae **DHCP integrado**.
- **Solución:** usar AdGuard para **DHCP + DNS**; no instalar dnsmasq del lab.

### `dnsmasq: cannot read /etc/homelab-dnsmasq.conf: Permission denied` (con sudo)
- **Causa:** **AppArmor** confina a dnsmasq a rutas estándar.
- **Solución:** usar una ruta permitida (`/etc/dnsmasq.d/*.conf`) o `aa-complain`.
  (En este lab se descartó dnsmasq del todo a favor de AdGuard.)

### El dnsmasq que aparece corriendo es de libvirt
- `--conf-file=/var/lib/libvirt/dnsmasq/default.conf`, `interface=virbr0`. Sirve
  solo `192.168.122.x`. **No tocar.**

### Un nombre no resuelve: `macbook-pro.home.lab.lan`
- **Causa:** el **dominio de búsqueda** de AdGuard es `lan` por defecto y macOS lo
  **anexa**.
- **Solución:** usar el FQDN exacto `macbook-pro.home.lab`, y/o cambiar el dominio
  local de AdGuard a `home.lab`.

### Nombres del lab no resuelven ni con `dig @10.0.1.1`
- **Causa:** AdGuard no tenía registro (equipos sin lease activo / dominio `lan`).
- **Solución:** **DNS rewrites** explícitos (nombre→IP) + renovar DHCP + fijar
  dominio local en `home.lab`.

### `No route to host` pese a que el DNS resuelve
- **Causa típica:** la IP del **DNS rewrite** no coincidía con la IP real/reserva
  (ej. `.10` vs `.100`), o el equipo no había **renovado DHCP** a su IP de reserva.
- **Solución:** alinear **reserva = rewrite = IP real** y renovar DHCP
  (`sudo ipconfig set en0 DHCP`).

## Conectividad

### `No route to host` ≠ ping bloqueado
- `No route to host` = **falló el ARP** (nadie responde en esa IP a nivel L2).
- `Request timeout` = el host está pero no contesta (posible firewall ICMP).

### ⏳ PENDIENTE: cliente↔cliente no se ven, pero el gateway sí llega a todos
- **Síntoma:** el ZimaBoard alcanza `10.0.1.10` y `10.0.1.11` (ambos `REACHABLE`
  en `ip neigh show dev eth1`), pero la MacBook (`.11`) **no** obtiene ARP del Mac
  mini (`.10`) y viceversa.
- **Hipótesis:** **aislamiento de puertos (Port Isolation)** en el switch TP-Link,
  o los equipos no están en el mismo switch/segmento.
- **Verificación:** `sudo arp -d <ip>; ping <ip>; arp -a | grep <ip>` → entrada
  `(incomplete)` confirma ARP sin respuesta.
- **Solución pendiente:**
  - Si el switch es **Easy Smart/Smart** (modelo termina en `E`): entrar a su UI
    (o *TP-Link Easy Smart Configuration Utility*) y **desactivar Port Isolation**.
  - Si es **unmanaged**: verificar que ambos equipos estén en el **mismo switch**.
- **Impacto:** NO afecta internet, servicios centralizados ni acceso remoto
  (Tailscale), que enrutan vía el ZimaBoard. Solo el tráfico directo LAN↔LAN.
- **Dato faltante:** modelo del switch TP-Link.

## macOS

### No se puede activar Remote Login por CLI
- `setremotelogin ... requires Full Disk Access`.
- **Solución:** activarlo por UI (Ajustes → General → Compartir → Inicio de sesión
  remoto), o dar Full Disk Access a la Terminal.

### Múltiples interfaces (Wi-Fi de casa + Ethernet del lab)
- Verificar la ruta: `route -n get <ip-lab>` → `interface:` debe ser la Ethernet
  del lab (la que tiene `10.0.1.x`).
- Si sale por Wi-Fi: reordenar servicios (Ajustes → Red → ··· → Ordenar servicios)
  o apagar Wi-Fi para la prueba.
