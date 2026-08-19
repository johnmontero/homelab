#!/usr/bin/env bash
# Etiquetas de nodo del homelab. Las labels NO se pasan por flags del k3s-agent en
# este clúster; se aplican con kubectl (idempotente). Ejecutar tras unir cada nodo.
set -euo pipefail

# Jetson Nano (arm64, GPU Tegra). `hardware=jetson` lo usa el nvidia-device-plugin.
for n in jetson-2gb-01.home.lab jetson-2gb-02.home.lab; do
  kubectl label node "$n" hardware=jetson accelerator=nvidia-tegra memory=2gb --overwrite
done
kubectl label node jetson-4gb-01.home.lab hardware=jetson accelerator=nvidia-tegra memory=4gb --overwrite

# ZimaBoard (amd64, control-plane, nodo de storage).
kubectl label node zimaboard2 hardware=zimaboard storage-node=true --overwrite

kubectl get nodes -L hardware,memory,accelerator,storage-node
