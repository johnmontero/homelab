---
name: protecso-deploy-pipeline
description: Pipeline de despliegue de PIVAS y la librería protecso_ui en el flujo Protecso (docker dev, commits en español, CI de GitHub Actions, rollout en homelab k3s). Úsalo como referencia al desplegar cambios de UI/lib o de PIVAS, o cuando el usuario pida "desplegar", "publicar el cambio", "subir a homelab".
triggers: desplegar cambio, pipeline de deploy, publicar cambio ui, bump protecso_ui, actualizar mix.lock, rollout homelab, ci pivas
---
# Pipeline de despliegue — Protecso (PIVAS + protecso_ui)

Procedimiento determinista para publicar un cambio. Las operaciones de git y build
ocurren donde están los repos (no dentro del pod de Crew); el **rollout** sí puede
dispararlo Crew con el skill `rollout-pivas`.

## Convenciones
- **Commits en español** (tipo Conventional en inglés: feat/fix/docs/chore…).
- **Compilar con `--warnings-as-errors`** y tests verdes antes de commitear.
- No hacer `push --force` ni tocar git config. No versionar secretos.

## Caso A — cambio en la librería `protecso_ui`
1. Editar componente/CSS. Compilar la lib:
   `docker run --rm -v "$PWD":/app -w /app cotejo-dev:latest sh -c "mix compile --warnings-as-errors"`
   y validar JS si aplica (`node --check`).
2. **Bump de versión** en `mix.exs` (semver).
3. Commit (español) + push a `main`. Anotar el commit SHA.
4. En **PIVAS** (`protecso-pivas-fs/app/src`): actualizar el **pin** de `protecso_ui`
   en `mix.lock` al nuevo SHA. Compilar PIVAS:
   `IMAGE=pivas-dev PROJECT_DIR=app/src docker-compose run --rm --no-deps phx /usr/local/bin/docker-entrypoint.sh sh -c "mix deps.get && mix compile --warnings-as-errors"`.
5. Commit del `mix.lock` (español) + push.

## Caso B — cambio solo en PIVAS
1. Editar. Compilar `--warnings-as-errors` + `mix test` (última suite verde: 152).
2. Commit (español) + push a `main`.

## CI y rollout (común)
1. GitHub Actions de `protecso-pivas-fs` construye la imagen y la publica en GHCR
   (`ghcr.io/protecso-sac/pivas-fs:latest`).
2. **Esperar CI verde** (status `completed` / conclusion `success`) para el commit.
3. **Rollout** en homelab: `kubectl -n pivas rollout restart deploy/pivas`
   (o el skill `rollout-pivas` desde Crew, que lo hace vía API con el SA).

## Notas
- El `mix.lock` de PIVAS fija `protecso_ui` a un commit git → **siempre** actualizar
  el pin cuando cambie la lib, si no PIVAS no ve el cambio.
- Idioma: documentación y comentarios en español neutro; identificadores en inglés.
