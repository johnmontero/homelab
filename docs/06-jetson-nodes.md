# Nodos Jetson Nano (arm64 / GPU Tegra)

Configuración a nivel de host de los 3 Jetson Nano que actúan como **agents** de
k3s. Documentado para poder **reflashear/reinstalar** un nodo y reintegrarlo.

## Inventario

| Nodo | IP | RAM | GPU | Rol k8s |
|------|----|-----|-----|---------|
| `jetson-4gb-01.home.lab` | 10.0.1.20 | 4 GB | 1× Tegra (Maxwell) | worker — postgres-prod |
| `jetson-2gb-01.home.lab` | 10.0.1.21 | 2 GB | 1× Tegra | worker |
| `jetson-2gb-02.home.lab` | 10.0.1.22 | 2 GB | 1× Tegra | worker |

- Acceso: `ssh zb` (ZimaBoard) y desde ahí `ssh jetson-4gb-01.home.lab` (usuario
  `devops`). Los Jetson **no** son alcanzables directamente desde fuera de la LAN.

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

## Notas

- Hoy las cargas de IA (Ollama/LocalAI/Kokoro) corren en el **ZimaBoard (CPU)**;
  la GPU de los Jetson está **anunciada** pero aún sin consumidores.
- Reflasheo: JetPack 4.6.x (L4T R32.7.x) con SDK Manager/balenaEtcher; reinstalar
  `nvidia-container-runtime`, luego el k3s agent y el drop-in de containerd.
