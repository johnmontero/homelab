# Homelab

Laboratorio de red y cómputo en casa, basado en un **ZimaBoard 2** que actúa como
**router de borde** (gateway + DHCP/DNS + NAT) de una subred aislada
`10.0.1.0/24`. Sirve para alojar servicios propios (Docker, runner de CI con
`act`, futuro entorno de pruebas/deploy de **Cotejo**) y los equipos de trabajo
(Mac mini, MacBook, Jetson).

## Topología

```
[ Router ISP / Casa ] (192.168.18.1)
          |
          ▼ (WAN: eth0 — DHCP 192.168.18.113)
   ┌──────────────────────┐
   │      ZIMABOARD 2      │  ← Gateway + DHCP/DNS (AdGuard) + NAT
   └──────────────────────┘
          | (LAN: eth1 — estática 10.0.1.1/24)
          ▼
   [ Switch TP-Link 8 puertos ]
          |
   ┌──────┼───────────┬───────────────┐
   ▼      ▼           ▼               ▼
 Mac mini  MacBook   Jetson        (otros)
 10.0.1.10 10.0.1.11  10.0.1.x
```

## Subredes en uso (no deben solaparse)

| Segmento | Subred | Interfaz |
|----------|--------|----------|
| Casa (WAN) | `192.168.18.0/24` | eth0 |
| **Lab (LAN)** | **`10.0.1.0/24`** | eth1 |
| VMs libvirt | `192.168.122.0/24` | virbr0 |
| ZeroTier (IceWhale) | `172.27.0.0/16` | ztqt46dh7q |
| Docker | `172.17.0.0/16` | docker0 |

## Componentes

| Rol | Implementación | Estado |
|-----|----------------|--------|
| Gateway / router | ZimaBoard 2 (eth0 WAN, eth1 LAN) | ✅ |
| NAT (LAN→WAN) | `homelab-nat.service` (systemd + iptables) | ✅ |
| DHCP + DNS | **AdGuard Home** (ya instalado en ZimaOS) | ✅ |
| Nombres locales | dominio `home.lab` (DNS rewrites + leases) | ✅ |
| Acceso remoto | **Tailscale** (subnet-router `10.0.1.0/24`) | ⏳ en curso |
| Orquestación | **k3s** (1 server + 3 agents) | ✅ |
| Datos | **CloudNativePG** (PostgreSQL dev/prod, pgvector) | ✅ |
| Object storage | **RustFS** (S3-compatible, ns `storage`) | ✅ |
| Backups BD | Barman Cloud Plugin → RustFS (PITR) | ⏳ pendiente |
| Cómputo/servicios | Docker (registry, runner `act`, etc.) | 🔜 |

## Equipos y direcciones fijas

| Equipo | Hostname | IP | MAC |
|--------|----------|----|-----|
| Mac mini M1 | `mac-mini` | `10.0.1.10` | `14:98:77:7b:3d:6f` |
| MacBook Pro M4 | `macbook-pro` | `10.0.1.11` | `d8:eb:97:b8:78:1c` |
| ZimaBoard 2 | `zimaboard` | `10.0.1.1` | — |

## Kubernetes (k3s) y plataforma de datos

Sobre la LAN corre un clúster **k3s** (1 server zimaboard + 3 agents Jetson) que
aloja los servicios propios y la **plataforma de datos PostgreSQL** con
**CloudNativePG** (aislamiento total `dev`/`prod`).

- Configuración declarativa: [`kubernetes/`](./kubernetes/) (aplicar para recrear/cambiar).
- Diseño del clúster: [`docs/04-kubernetes-cluster.md`](./docs/04-kubernetes-cluster.md).
- PostgreSQL (CNPG) dev/prod + backups: [`docs/05-postgres-cnpg.md`](./docs/05-postgres-cnpg.md).

## Documentación

- [Configuración del router ZimaBoard](./docs/01-router-zimaboard.md) — WAN/LAN, NAT, DHCP/DNS, nombres.
- [Acceso remoto con Tailscale](./docs/02-acceso-remoto-tailscale.md)
- [Clúster Kubernetes (k3s)](./docs/04-kubernetes-cluster.md) — nodos, arquitectura, storage.
- [PostgreSQL con CloudNativePG](./docs/05-postgres-cnpg.md) — dev/prod, backups, runbooks.
- [Solución de problemas](./docs/03-troubleshooting.md)

## Relación con Cotejo

Este homelab es el entorno donde se ensayará el **deploy de Cotejo** (Docker +
runner `act`) antes de AWS. Ver el ADR de despliegue en `protecso-cotejo-docs`
(`architecture/decisions/0008-despliegue-multi-tenant-y-ambientes.md`) y la guía
de CI con `act` (`guides/ci-cd-con-act-en-ec2.md`).
