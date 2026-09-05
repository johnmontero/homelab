# Runbook: Incorporar un Jetson Nano como nodo k3s

Procedimiento **validado** (2026-09) para dar de alta un Jetson Nano nuevo (o
reflasheado) como *agent* de k3s. Cubre las variantes **4GB** (sin taint) y **2GB**
(con taint `tier=low:NoSchedule`).

| Dato | Valor |
|------|-------|
| Control-plane (API) | `https://10.0.1.1:6443` (zimaboard2) |
| Versión k3s | `v1.30.14+k3s2` (pinear, igual al server) |
| Usuario SSH | `devops` |
| Naming | `jn{RAM}-{NN}` → `jn4gb-02`, `jn2gb-03` |
| IPs | 4GB → `10.0.1.2x` · 2GB → `10.0.1.3x` |

---

## 0. (Solo si el nombre ya existió) limpiar registro fantasma

Si vas a reusar un `--node-name` que ya estuvo en el clúster, borra el objeto y su
*node-password* para permitir un registro limpio (evita "Node password rejected"):

```bash
kubectl delete node <nombre> --ignore-not-found
kubectl -n kube-system delete secret <nombre>.node-password.k3s --ignore-not-found
```

## 1. Flashear la microSD

- 4GB: **"Jetson Nano Developer Kit SD Card Image"** (JetPack 4.6.x / L4T R32.7.x).
- 2GB: **"Jetson Nano 2GB Developer Kit SD Card Image"** (misma familia).
- Grabar con **balenaEtcher**.

## 2. Primer arranque

- `oem-config`: usuario **`devops`**, hostname **`jnXgb-NN`**, zona horaria/teclado.
- Conectar Ethernet (Jetson Mate) y anotar la IP (reservar por MAC en el router).
- SSH viene habilitado. Verificar desde la ZimaBoard: `ssh devops@<IP>`.
  > El ICMP suele estar filtrado: usar `nc -z <IP> 22` en vez de `ping`.

## 3. Preparar el SO (en el nodo)

```bash
# curl no viene preinstalado en JetPack
sudo apt-get update && sudo apt-get install -y curl

# Desactivar GUI (libera RAM; imprescindible en 2GB)
sudo systemctl set-default multi-user.target
sudo systemctl disable --now display-manager 2>/dev/null || true

# cgroup de memoria — OBLIGATORIO para k3s en Jetson (si no, el kubelet falla)
# Añade a la línea APPEND de /boot/extlinux/extlinux.conf:
sudo sed -i '/^\s*APPEND/ s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/extlinux/extlinux.conf
sudo reboot
```

Verificar tras el reboot: `cat /proc/cgroups | awk '/^memory/{print $4}'` → debe ser `1`.

## 4. Unir al clúster (en el nodo)

Token del server (en la ZimaBoard): `sudo cat /var/lib/rancher/k3s/server/node-token`.

**Nodo 4GB** (sin taint):
```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION=v1.30.14+k3s2 \
  K3S_URL=https://10.0.1.1:6443 \
  K3S_TOKEN=<token-del-server> \
  INSTALL_K3S_EXEC="agent --node-name jn4gb-NN \
    --node-label board=jetson-nano --node-label mem=4gb \
    --kubelet-arg=fail-swap-on=false" \
  sh -
```

**Nodo 2GB** (con taint):
```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION=v1.30.14+k3s2 \
  K3S_URL=https://10.0.1.1:6443 \
  K3S_TOKEN=<token-del-server> \
  INSTALL_K3S_EXEC="agent --node-name jn2gb-NN \
    --node-label board=jetson-nano --node-label mem=2gb \
    --node-taint tier=low:NoSchedule \
    --kubelet-arg=fail-swap-on=false" \
  sh -
```

> Si `curl` falla en los repos de 18.04, usar `wget -qO- https://get.k3s.io | ... sh -`.

## 5. Verificar (desde el Mac)

```bash
kubectl get node jnXgb-NN -o wide
kubectl get node jnXgb-NN -o jsonpath='{.metadata.labels.board}/{.metadata.labels.mem} {range .spec.taints[*]}{.key}={.value}:{.effect}{end}{"\n"}'
```

Debe quedar `Ready`, `arm64`, kubelet `v1.30.14+k3s2`, con sus labels (y taint en 2GB).

## 6. (Opcional) Habilitar GPU Tegra

Solo si se van a correr cargas con GPU. Requiere 4 cosas (todas necesarias):

1. **Runtime en el nodo** (JetPack la trae; si falta):
   ```bash
   command -v nvidia-container-runtime || sudo apt-get install -y nvidia-container-runtime
   ```
2. **Drop-in de containerd** (no tocar el `config.toml` de k3s):
   `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.d/nvidia.toml`
   ```toml
   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia"]
     runtime_type = "io.containerd.runc.v2"
   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia".options]
     BinaryName = "/usr/bin/nvidia-container-runtime"
   ```
   Luego `sudo systemctl restart k3s-agent`.
3. **Label** `hardware=jetson` (lo selecciona el device-plugin):
   ```bash
   kubectl label node jnXgb-NN hardware=jetson accelerator=nvidia-tegra --overwrite
   ```
4. **Toleration** al taint `tier=low` en el DaemonSet (ya incluida en
   `kubernetes/platform/nvidia-device-plugin/daemonset.yaml`) — solo relevante para 2GB.

> ⚠️ **Orden importante**: primero 1+2 en el nodo, DESPUÉS 3 (label). Si aplicas el
> label antes de tener el drop-in, el pod del device-plugin entra en CrashLoopBackOff.

## 7. DNS

- Agregar la reescritura `jnXgb-NN.home.lab → <IP>` en AdGuard.

---

## Errores comunes

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `curl: command not found` | JetPack no trae curl | `apt-get install -y curl` o usar `wget` |
| Kubelet no arranca / `NotReady` | Falta cgroup de memoria | Paso 3 (extlinux) + reboot |
| "Node password rejected" | Nombre reusado con password viejo | Paso 0 (borrar node + secret) |
| `No route to host` desde el Mac | Los Jetson cuelgan del ZimaBoard | Operar vía `ssh zb` (relay) |
