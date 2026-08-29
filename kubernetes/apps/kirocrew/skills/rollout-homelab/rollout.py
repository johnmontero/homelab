#!/usr/bin/env python3
"""Reinicia (rollout restart) un Deployment del homelab vía la API de Kubernetes.

Genérico para cualquier app del homelab: el namespace y el deployment se pasan
por ROLLOUT_NS / ROLLOUT_DEPLOY (sin default de app, para no reiniciar la
equivocada por descuido). Usa el token del ServiceAccount montado en el pod, sin
requerir `kubectl`. Equivale a `kubectl rollout restart`: parcha la anotación
`kubectl.kubernetes.io/restartedAt` en spec.template, forzando un rollout.

Uso:
    ROLLOUT_NS=pivas  ROLLOUT_DEPLOY=pivas  python3 rollout.py
    ROLLOUT_NS=pulse  ROLLOUT_DEPLOY=pulse  python3 rollout.py

Requiere que el RBAC (kubernetes/apps/kirocrew/rbac.yaml) permita patch de
deployments en el namespace destino. Solo funciona dentro del pod de Kiro Crew.
"""
import datetime
import json
import os
import ssl
import sys
import urllib.request

SA = "/var/run/secrets/kubernetes.io/serviceaccount"
NS = os.environ.get("ROLLOUT_NS")
DEPLOY = os.environ.get("ROLLOUT_DEPLOY")


def main() -> int:
    if not NS or not DEPLOY:
        print(
            "ERROR: faltan ROLLOUT_NS y/o ROLLOUT_DEPLOY. "
            "Ej: ROLLOUT_NS=pivas ROLLOUT_DEPLOY=pivas python3 rollout.py",
            file=sys.stderr,
        )
        return 2
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
