# Runbook: Envoy Gateway data-plane crashea (tcmalloc mmap / vm.max_map_count)

El pod del data-plane `envoy-default-homelab-gateway-*` entra en CrashLoopBackOff:
el contenedor `envoy` muere con error de **tcmalloc** al no poder hacer `mmap`.

## Síntoma

`kubectl -n envoy-gateway-system logs <pod> -c envoy --previous`:

```
tcmalloc/system-alloc.cc: MmapAligned() failed - unable to allocate ... is
something limiting address placement? ... 1073741824 1073741824
tcmalloc/arena.cc: FATAL ERROR: Out of memory trying to allocate internal
tcmalloc data ... 131072 632
```

- `exitCode: 133`, contenedor `envoy` `ready=false`; el sidecar `shutdown-manager`
  sigue vivo → el pod queda **1/2**.

## Diagnóstico (2026-08-25)

- El contenedor `envoy` **no tiene límite de memoria** (solo requests
  cpu=100m/mem=512Mi), el nodo tenía memoria disponible y
  `vm.overcommit_memory=1` (permisivo). Aun así falla el `mmap` incluso de 128KB.
- Con overcommit permisivo y sin límite de RSS, un `mmap` que devuelve ENOMEM
  apunta al límite de **número de mapas de memoria por proceso**:
  `vm.max_map_count=65530` (el default), insuficiente para las arenas por-CPU de
  tcmalloc de Envoy.
- Se disparó durante el incidente de memoria/disk-pressure de zimaboard2; un pod
  fresco seguía crasheando hasta que se estabilizó la memoria del nodo.

## Fix (root en zimaboard2)

Subir `vm.max_map_count` de forma persistente:

```bash
# aplicar ahora
sudo sysctl -w vm.max_map_count=262144
# persistir
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-envoy-mmap.conf
sudo sysctl --system
# recrear el pod del data-plane para que tome el nuevo límite
sudo k3s kubectl -n envoy-gateway-system delete pod \
  -l gateway.envoyproxy.io/owning-gateway-name=homelab-gateway
# verificar 2/2 Running
sudo k3s kubectl -n envoy-gateway-system get pods \
  -l gateway.envoyproxy.io/owning-gateway-name=homelab-gateway -w
```

### Si un pod queda "Terminating" colgado
Tras un blip del nodo, el pod viejo puede no morir. Forzar:
```bash
sudo k3s kubectl -n envoy-gateway-system delete pod <pod> --grace-period=0 --force
```

## Plan B (si persiste tras subir max_map_count)

Bajar la concurrencia de Envoy (menos arenas por-CPU) vía un recurso `EnvoyProxy`
referenciado por la GatewayClass, con `--concurrency 2`, y/o fijar límites de
memoria al contenedor. Documentar aparte si se llega a necesitar.

## Caveats

- ZimaOS es appliance: un update del SO puede resetear `/etc/sysctl.d`. Si vuelve
  el crash tras un update, re-aplicar.

## Estado (2026-08-25)

- [x] Data-plane recuperado a 2/2 (pod `wbmps`).
- [x] `vm.max_map_count=262144` **aplicado** (runtime) y **persistido** en
      `/etc/sysctl.d/99-envoy-mmap.conf` (sobrevive reboots).

**✅ Resuelto.** (Caveat ZimaOS: re-verificar tras un update del SO.)
