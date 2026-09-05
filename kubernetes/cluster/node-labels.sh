#!/usr/bin/env bash
# Etiquetas y taints de los nodos del homelab (idempotente). Ejecutar tras unir un nodo.
# Fuente de verdad del esquema de labels/taints; alineado con docs/06-jetson-nodes.md
# y docs/11-runbook-incorporar-nodo-jetson.md.
set -euo pipefail

# ── Jetson Nano (arm64, GPU Tegra) ──
# board=jetson-nano, mem=<ram>  → informativos / scheduling por RAM.
# hardware=jetson               → lo usa el nvidia-device-plugin (nodeSelector).
# tier=low:NoSchedule (solo 2GB)→ aísla los 2GB de la carga general.
#
# ⚠️ GPU: el nvidia-device-plugin además requiere que el nodo tenga instalada la
#    `nvidia-container-runtime` y (para los 2GB) una toleration a `tier=low`.
#    Ver docs/06-jetson-nodes.md.

for n in jn4gb-01 jn4gb-02; do
  kubectl label node "$n" hardware=jetson accelerator=nvidia-tegra board=jetson-nano mem=4gb --overwrite
done

for n in jn2gb-01 jn2gb-02 jn2gb-03; do
  kubectl label node "$n" hardware=jetson accelerator=nvidia-tegra board=jetson-nano mem=2gb --overwrite
  kubectl taint node "$n" tier=low:NoSchedule --overwrite
done

# ── ZimaBoard (amd64, control-plane, nodo de storage) ──
kubectl label node zimaboard2 hardware=zimaboard storage-node=true --overwrite

kubectl get nodes -L hardware,board,mem,storage-node
