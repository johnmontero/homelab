---
name: protecso-deploy-pipeline
description: Pipeline de despliegue de PIVAS, Pulse y la librería protecso_ui en el flujo Protecso (docker dev, commits en español, CI de GitHub Actions, rollout en homelab k3s). Úsalo como referencia al desplegar cambios de UI/lib, PIVAS o Pulse, o cuando el usuario pida "desplegar", "publicar el cambio", "subir a homelab".
triggers: desplegar cambio, pipeline de deploy, publicar cambio ui, bump protecso_ui, actualizar mix.lock, rollout homelab, ci pivas, ci pulse, desplegar pulse
---
# Pipeline de despliegue — Protecso (PIVAS + Pulse + protecso_ui)

Procedimiento determinista para publicar un cambio. Las operaciones de git y build
ocurren donde están los repos (no dentro del pod de Crew); el **rollout** sí puede
dispararlo Crew con el skill `rollout-pivas`.

> Canon completo (para sesiones de Kiro): `protecso-kiro-workflow/.kiro/steering/`
> `05-pipeline-despliegue.md` y `06-paleta-de-marca.md`.

## Convenciones
- **Commits en español** (tipo Conventional en inglés: feat/fix/docs/style/refactor/chore…).
- **Compilar con `--warnings-as-errors`** y tests verdes antes de commitear.
- **Solo commitear/pushear cuando el usuario lo pida.** No `push --force` ni tocar git config. No versionar secretos.

## Caso A — cambio en la librería `protecso_ui`
1. Editar componente/CSS. Compilar la lib:
   `docker run --rm -v "$PWD":/app -w /app cotejo-dev:latest sh -c "mix compile --warnings-as-errors"`
   y validar JS si aplica (`node --check`).
2. **Bump de versión** en `mix.exs` (semver).
3. Commit (español) + push a `main`. Anotar el commit SHA.
4. En cada app consumidora (p. ej. `protecso-pivas-fs/app/src`): actualizar el **pin** de
   `protecso_ui` en `mix.lock` al nuevo SHA. Compilar:
   `IMAGE=pivas-dev PROJECT_DIR=app/src docker-compose run --rm --no-deps phx /usr/local/bin/docker-entrypoint.sh sh -c "mix deps.get && mix compile --warnings-as-errors"`.
5. Commit del `mix.lock` (español) + push.

## Caso B — cambio solo en PIVAS
1. Editar. Compilar `--warnings-as-errors` + `mix test` (última suite verde: **156**).
   Si tocaste CSS/JS: `mix assets.build`.
2. Commit (español) + push a `main`.

## Caso C — cambio solo en Pulse
Mismo estándar. Repo `protecso-pulse-fs`, imagen `ghcr.io/protecso-sac/pulse-fs`
(privada → pull secret `ghcr-creds` en el SA `default` del ns). Host `pulse.nx73.app`,
puerto 4002. Migraciones en el initContainer con `Pulse.Release.migrate/0`.

## CI y rollout (común)
1. GitHub Actions construye la imagen y la publica en GHCR (`:latest`).
2. **Esperar CI verde** con un poll **single-shot** (los loops se abortan; repetir tras
   `sleep` si sigue `in_progress`). Para PIVAS:
   ```bash
   TOKEN="$(tr -d '\n\r' < <ruta>/homelab/github.token)"; \
   curl -s -H "Authorization: Bearer $TOKEN" \
     "https://api.github.com/repos/Protecso-SAC/protecso-pivas-fs/actions/runs?per_page=1" \
     | python3 -c "import sys,json; r=json.loads(sys.stdin.read(), strict=False)['workflow_runs'][0]; print(r['head_sha'][:8], r['status'], r['conclusion'])"
   ```
   Para Pulse: mismo comando contra `Protecso-SAC/protecso-pulse-fs`.
3. **Rollout** en homelab (tras `completed`/`success`):
   - PIVAS: skill `rollout-pivas` (`python3 rollout.py`) o `kubectl -n pivas rollout restart deploy/pivas`.
   - Verificar: `kubectl -n pivas rollout status deploy/pivas --timeout=180s`.
   - Pulse: `kubectl -n pulse rollout restart deploy/pulse` + `rollout status` (RBAC de Crew
     hoy solo cubre el ns `pivas`; para Pulse desde Crew habría que ampliar el RBAC).

## Utilidad: reiniciar un caso de PIVAS (SOLO pruebas / homelab)
Borra evidencia/captura de un caso y lo deja en estado inicial. Requiere `ALLOW_CLAIM_RESET=true`.
```bash
POD=$(kubectl -n pivas get pods -l app=pivas -o jsonpath='{.items[0].metadata.name}')
kubectl -n pivas exec "$POD" -c pivas -- sh -c \
  'ALLOW_CLAIM_RESET=true /app/rel/pivas/bin/pivas eval "Pivas.Release.reset_claim(\"SIN-XXXXXXXX\")"'
```

## Notas
- El `mix.lock` fija `protecso_ui` a un commit git → **siempre** actualizar el pin cuando
  cambie la lib, si no la app no ve el cambio.
- Color de marca por app (ver `06-paleta-de-marca.md`): PIVAS azul-cian, Cotejo índigo,
  Pulse violeta.
- Idioma: documentación y comentarios en español neutro; identificadores en inglés.
- Los commits del repo `homelab` suelen quedar locales: recordar pushear al cerrar.
