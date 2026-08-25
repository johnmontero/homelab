# Runbook: mover el data-dir de k3s al SSD (zimaboard2)

Reubicar el data-dir de k3s desde `/DATA` (eMMC de 45G, se llena y provoca
`disk-pressure`) al **SSD de 224G** (`/dev/sda`, btrfs), que está casi vacío.

## Contexto / diagnóstico (2026-08-25)

- Nodo afectado: **zimaboard2** (control-plane amd64; ahí corren la BD, PIVAS,
  Kiro Crew, etc.).
- `/DATA` = `mmcblk0p8`, 45G, ~84% usado. El kubelet evicta al cruzar el umbral
  de `imagefs` (~15% libre) → `disk-pressure` intermitente ("flapping").
- **k3s** arranca por systemd (`/etc/systemd/system/k3s.service`, `/opt/bin/k3s
  server`) **sin `--data-dir`** → usa el default `/var/lib/rancher/k3s`, que es un
  **symlink → `/DATA/k3s/k3s`**.
- **SSD**: `/dev/sda`, **btrfs**, `UUID=d69e81fa-4300-4896-b56e-aea864fb2778`,
  montado por CasaOS en `/media/SSD-Storage` (no está en `/etc/fstab`).
- Incidente que lo destapó: LocalAI en crashloop acumuló pods muertos (imágenes
  multi-GB) que llenaron `/DATA` → disk-pressure → tumbó `postgres-dev` y bloqueó
  deploys. LocalAI quedó apagado (`kubernetes/ai-agents/localai.yaml`, replicas 0).

## Diseño

Montar un **subvolumen btrfs dedicado del SSD directamente en
`/var/lib/rancher/k3s`** mediante un **systemd mount unit** (monta por UUID, es
independiente de CasaOS), y ordenar `k3s.service` con `Requires/After` de ese
mount para que **k3s nunca arranque sin el SSD** (si no, vería el data-dir vacío
y rompería el cluster).

> Ejecutar en ventana de mantenimiento: al parar k3s, los workloads de zimaboard2
> quedan abajo unos minutos mientras copia (~10G+). Requiere **root** en el nodo.

## Pasos

### 1) Parar k3s
```bash
sudo systemctl stop k3s
```

### 2) Crear subvolumen en el SSD y copiar el data-dir (datos en reposo)
```bash
sudo btrfs subvolume list /media/SSD-Storage        # debe listar sin error
sudo btrfs subvolume create /media/SSD-Storage/@k3s
sudo rsync -aHAX --numeric-ids --info=progress2 /DATA/k3s/k3s/ /media/SSD-Storage/@k3s/
```

### 3) Convertir el symlink en punto de montaje real
```bash
sudo rm /var/lib/rancher/k3s
sudo mkdir -p /var/lib/rancher/k3s
```

### 4) Mount unit de systemd (nombre = ruta: `var-lib-rancher-k3s.mount`)
```bash
sudo tee /etc/systemd/system/var-lib-rancher-k3s.mount >/dev/null <<'EOF'
[Unit]
Description=k3s data-dir en SSD (btrfs subvol @k3s)
Before=k3s.service

[Mount]
What=/dev/disk/by-uuid/d69e81fa-4300-4896-b56e-aea864fb2778
Where=/var/lib/rancher/k3s
Type=btrfs
Options=rw,noatime,subvol=@k3s

[Install]
WantedBy=local-fs.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now var-lib-rancher-k3s.mount
mount | grep rancher/k3s     # /dev/sda en /var/lib/rancher/k3s
ls /var/lib/rancher/k3s      # deben verse los datos copiados (server, agent, storage…)
```

### 5) Drop-in para que k3s dependa del mount (clave anti-arranque-vacío)
```bash
sudo mkdir -p /etc/systemd/system/k3s.service.d
sudo tee /etc/systemd/system/k3s.service.d/10-ssd-datadir.conf >/dev/null <<'EOF'
[Unit]
RequiresMountsFor=/var/lib/rancher/k3s
Requires=var-lib-rancher-k3s.mount
After=var-lib-rancher-k3s.mount
EOF

sudo systemctl daemon-reload
```

### 6) Arrancar k3s y verificar
```bash
sudo systemctl start k3s
sudo k3s kubectl get nodes -o wide
df -h /var/lib/rancher/k3s                                    # debe mostrar /dev/sda
sudo k3s kubectl get pods -A | grep -vE "Running|Completed"   # esperar a que levante
```

### 7) Prueba de reboot (CRÍTICA — valida el orden de montaje)
```bash
sudo reboot
# tras reiniciar:
df -h /var/lib/rancher/k3s     # /dev/sda
sudo k3s kubectl get nodes     # Ready
```

### 8) Recuperar espacio en /DATA (solo tras validar salud y reboot OK)
```bash
sudo mv /DATA/k3s/k3s /DATA/k3s/k3s.OLD   # backup temporal
# verificar el cluster un rato… y luego:
sudo rm -rf /DATA/k3s/k3s.OLD
df -h /DATA
```

## Rollback (si k3s no arranca en el paso 6)
```bash
sudo systemctl stop k3s
sudo systemctl disable --now var-lib-rancher-k3s.mount
sudo rm -f /etc/systemd/system/var-lib-rancher-k3s.mount
sudo rm -rf /etc/systemd/system/k3s.service.d/10-ssd-datadir.conf
sudo rmdir /var/lib/rancher/k3s
sudo ln -s /DATA/k3s/k3s /var/lib/rancher/k3s   # restaura el symlink original
sudo systemctl daemon-reload
sudo systemctl start k3s
```

## Caveats

- **ZimaOS/CasaOS es appliance**: una actualización del SO podría resetear los
  units de `/etc/systemd/system`. Si tras un update k3s no monta el SSD, re-aplica
  pasos 4–5. Verificar con `df -h /var/lib/rancher/k3s` tras cada update.
- La copia (paso 2) es segura porque k3s está parado → los PVCs local-path
  (incluida la BD `postgres-dev`) se copian en reposo.
- Se monta el SSD **por UUID e independiente de CasaOS**, así el orden de arranque
  no depende de cómo/cuándo monte CasaOS su copia.
- No toca las imágenes del containerd de CasaOS (moby), solo el data-dir de k3s.

## Estado (2026-08-25)

Migración **funcionalmente aplicada** (pasos 1–6):
- [x] Subvol `@k3s` creado en el SSD y datos copiados (~31G en `/dev/sda`).
- [x] `/var/lib/rancher/k3s` es punto de montaje real (ya no symlink).
- [x] `var-lib-rancher-k3s.mount` **active** y **enabled** (monta en boot).
- [x] Drop-in `10-ssd-datadir.conf` cargado: k3s tiene `Requires`+`After` del mount.
- [x] `df /var/lib/rancher/k3s` → `/dev/sda`; cluster sano (nodos Ready).

- [x] **Paso 7 — prueba de reboot** (2026-08-25 02:18): tras reiniciar, el SSD
      montó antes de k3s (`/var/lib/rancher/k3s` = `/dev/sda[/@k3s]`), cluster
      Ready y sin pods caídos. Orden de montaje validado.

**Pendiente para cerrar:**
- [ ] **Paso 8 — recuperar espacio**: borrar `/DATA/k3s/k3s` (copia vieja
      huérfana, ~31G). **Hasta hacerlo, `/DATA` sigue al 84%** y el riesgo de
      disk-pressure NO desaparece: este paso es el que entrega el beneficio.
