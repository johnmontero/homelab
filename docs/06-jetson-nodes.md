# Nodos Jetson Nano (arm64 / GPU Tegra)

Configuración a nivel de host de los 3 Jetson Nano que actúan como **agents** de
k3s. Documentado para poder **reflashear/reinstalar** un nodo y reintegrarlo.

## Inventario

> Renombrado (2026-09): naming `jn{RAM}-{NN}` y nuevo esquema de IPs
> (**4GB → 10.0.1.2x**, **2GB → 10.0.1.3x**). Los antiguos `jetson-*` (10.0.1.20/22/101)
> quedaron obsoletos y se eliminaron del clúster.

| Nodo | IP | RAM | Labels | Taint | Rol k8s |
|------|----|-----|--------|-------|---------|
| `jn4gb-01` | 10.0.1.21 | 4 GB | `board=jetson-nano, mem=4gb` | — | worker |
| `jn4gb-02` | 10.0.1.22 | 4 GB | `board=jetson-nano, mem=4gb` | — | worker |
| `jn2gb-01` | 10.0.1.31 | 2 GB | `board=jetson-nano, mem=2gb` | `tier=low:NoSchedule` | worker |
| `jn2gb-02` | 10.0.1.32 | 2 GB | `board=jetson-nano, mem=2gb` | `tier=low:NoSchedule` | worker |
| `jn2gb-03` | 10.0.1.33 | 2 GB | `board=jetson-nano, mem=2gb` | `tier=low:NoSchedule` | worker |

- Todos `arm64`, kubelet **v1.30.14+k3s2**, agents de k3s. Control-plane: `zimaboard2` (10.0.1.1).
- Los 2GB llevan taint `tier=low:NoSchedule` para aislarlos de la carga general
  (solo cargas que lo toleren explícitamente). Los 4GB sin taint.
- Acceso: `ssh zb` (ZimaBoard) y desde ahí `ssh devops@<IP>`. Los Jetson **no** son
  alcanzables directamente desde fuera de la LAN (cuelgan del segmento del ZimaBoard).
- Alta de un nodo nuevo: ver [`11-runbook-incorporar-nodo-jetson.md`](./11-runbook-incorporar-nodo-jetson.md).

## Resolución de nombres (DNS)

Los hostnames están registrados como **rewrites estáticos en AdGuard**
(Filtros → Reescrituras DNS):

| Dominio | Respuesta |
|---------|-----------|
| `jn4gb-01.home.lab` | `10.0.1.21` |
| `jn4gb-02.home.lab` | `10.0.1.22` |
| `jn2gb-01.home.lab` | `10.0.1.31` |
| `jn2gb-02.home.lab` | `10.0.1.32` |
| `jn2gb-03.home.lab` | `10.0.1.33` |

> ⚠️ Pendiente: actualizar las reescrituras de AdGuard al nuevo naming/IPs (arriba).
> Las entradas viejas `jetson-*` deben eliminarse.

> **Alcanzabilidad (importante):** el DNS resuelve desde toda la LAN, pero los
> Jetson **solo son accesibles desde el ZimaBoard** (SSH/TCP abierto). Desde la
> MacBook (`10.0.1.11`) el nombre resuelve pero **no hay ruta L2** a esas IPs
> (cuelgan del segmento del ZimaBoard). Para acceder desde la MacBook hay que
> resolver la topología L2 (mismo switch), rutear por el ZimaBoard o usar el
> subnet-router de Tailscale. El **ICMP/ping está filtrado** en los Jetson: usar
> TCP (p. ej. `nc -z <host> 22`) para verificar acceso, no `ping`.

## Sistema base (host)

| Ítem | Valor |
|------|-------|
| OS | Ubuntu 18.04.6 LTS (aarch64) |
| L4T / JetPack | **R32.7.6** (`nvidia-l4t-core 32.7.6`) → JetPack 4.6.x |
| Kernel | `4.9.337-tegra` |
| Runtime GPU | `nvidia-container-runtime` + `nvidia-container-toolkit` (`/usr/bin`) |
| Swap | `/swapfile` 4 GB + 4× zram (~248 MB en 2 GB, ~496 MB en 4 GB) |
| Disco | eMMC/SD (`/dev/mmcblk0p1`, ~59 GB en el 4 GB) |
| Power | `nvpmodel` MAXN |

## k3s agent

- Versión: **v1.30.14+k3s2** (igual que el server).
- Unit: `k3s-agent.service` (+ `k3s-agent.service.env` con `K3S_URL`/`K3S_TOKEN`).
- Arranque (observado):
  ```
  /usr/local/bin/k3s agent --flannel-iface eth0 --prefer-bundled-bin
  ```
- Instalación típica (reintegrar un nodo):
  ```bash
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION=v1.30.14+k3s2 \
    K3S_URL=https://10.0.1.1:6443 \
    K3S_TOKEN=<token-del-server> \
    sh -s - agent --flannel-iface eth0 --prefer-bundled-bin
  ```
  > El token está en el server: `sudo cat /var/lib/rancher/k3s/server/node-token`.
- **Labels:** se aplican con `kubectl` (no por flags). Ver
  `kubernetes/cluster/node-labels.sh`.

## GPU en containerd (habilitar la NVIDIA runtime)

k3s trae su propio containerd. La runtime `nvidia` se registra con un drop-in
(no se toca el `config.toml` generado por k3s):

`/var/lib/rancher/k3s/agent/etc/containerd/config.toml.d/nvidia.toml`
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia"]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia".options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
```
- La runtime **no** es la default (los pods normales usan `runc`). Para usar la
  GPU, el pod declara `runtimeClassName: nvidia` (existe la `RuntimeClass nvidia`).
- El `nvidia-device-plugin` (DaemonSet, `nodeSelector: hardware=jetson`) expone
  `nvidia.com/gpu: 1` por nodo. Manifiesto: `kubernetes/platform/nvidia-device-plugin/`.
- Reiniciar containerd/k3s-agent tras crear el drop-in:
  `sudo systemctl restart k3s-agent`.

## GPU en contenedores — estado y limitación conocida (2026-09)

| Aspecto | Estado |
|---------|--------|
| Anuncio `nvidia.com/gpu: 1` en los 5 Jetson | ✅ Funciona (device-plugin `Running`) |
| `nvidia-container-runtime` + CSV L4T + drop-in containerd | ✅ Presentes en los 5 |
| **Passthrough real a un contenedor** | ❌ **Falla** (ver abajo) |

Un pod que pide `nvidia.com/gpu` con `runtimeClassName: nvidia` falla al crear el
contenedor con:
```
nvidia-container-cli: device error: tegra: unknown device: unknown
```
Es el problema clásico de **Jetson/Tegra**: el device-plugin estándar pasa un device-ID
que `nvidia-container-cli` intenta resolver como GPU discreta, inexistente en Tegra. Se
probó `mode = "csv"` en `/etc/nvidia-container-runtime/config.toml` (nodo `jn4gb-01`) y
**no** lo resolvió: el prestart hook sigue invocando `nvidia-container-cli`.

**Pendiente (tarea aparte)** para habilitar GPU real: device-plugin Tegra-aware
(`jetson-containers`) o inyección puramente por CSV sin el hook de `nvidia-container-cli`
/ tuning de `NVIDIA_VISIBLE_DEVICES`. **No bloquea nada hoy**: las cargas normales usan
`runc`; solo fallaría un pod que pida GPU explícitamente.

## Notas

- Hoy las cargas de IA (Ollama/LocalAI/Kokoro) corren en el **ZimaBoard (CPU)**;
  la GPU de los Jetson está **anunciada** pero **no usable aún** en contenedores
  (ver limitación arriba). Sin consumidores por ahora.
- Reflasheo: JetPack 4.6.x (L4T R32.7.x) con SDK Manager/balenaEtcher; reinstalar
  `nvidia-container-runtime`, luego el k3s agent y el drop-in de containerd.
