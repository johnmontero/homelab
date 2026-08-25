#!/usr/bin/env python3
"""Reinicia (rollout restart) un Deployment vía la API de Kubernetes.

Usa el token del ServiceAccount montado en el pod (kirocrew-deployer), sin
requerir `kubectl`. Equivale a `kubectl rollout restart`: parcha la anotación
`kubectl.kubernetes.io/restartedAt` en spec.template, lo que fuerza un rollout.

Uso:
    python3 rollout.py                 # ns=pivas, deploy=pivas (por defecto)
    ROLLOUT_NS=pivas ROLLOUT_DEPLOY=pivas python3 rollout.py

Requiere el RBAC de kubernetes/apps/kirocrew/rbac.yaml (patch de deployments en
el ns destino). Solo funciona dentro del pod de Kiro Crew.
"""
import datetime
import json
import os
import ssl
import sys
import urllib.request

SA = "/var/run/secrets/kubernetes.io/serviceaccount"
NS = os.environ.get("ROLLOUT_NS", "pivas")
DEPLOY = os.environ.get("ROLLOUT_DEPLOY", "pivas")


def main() -> int:
    try:
        token = open(f"{SA}/token", encoding="utf-8").read().strip()
    except OSError:
        print("ERROR: no hay token de ServiceAccount montado; ¿corre dentro del pod?", file=sys.stderr)
        return 2

    host = os.environ.get("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc")
    port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
    url = f"https://{host}:{port}/apis/apps/v1/namespaces/{NS}/deployments/{DEPLOY}"
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()

    patch = json.dumps(
        {"spec": {"template": {"metadata": {"annotations": {
            "kubectl.kubernetes.io/restartedAt": now
        }}}}}
    ).encode()

    ctx = ssl.create_default_context(cafile=f"{SA}/ca.crt")
    req = urllib.request.Request(
        url,
        data=patch,
        method="PATCH",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/strategic-merge-patch+json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            print(f"OK: rollout restart {NS}/{DEPLOY} -> HTTP {resp.status} @ {now}")
            return 0
    except urllib.error.HTTPError as e:
        print(f"ERROR HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
