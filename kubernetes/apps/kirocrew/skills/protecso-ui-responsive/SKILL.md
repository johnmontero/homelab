---
name: protecso-ui-responsive
description: Convenciones de UI responsive del design system Protecso (protecso_ui) aplicadas en PIVAS/Cotejo/Pulse. Úsalo al diseñar o modificar vistas Phoenix/LiveView (tablas, listados, detalles, modales, formularios) para móvil/tablet/desktop, o cuando el usuario pida ajustes responsive.
triggers: responsive, móvil, tablet, tabla a tarjetas, menú de acciones, protecso_ui, diseño de vista, ajuste de UI
---
# Convenciones de UI responsive — Protecso (protecso_ui)

Reglas consolidadas del design system `protecso_ui` (Elixir/Phoenix, Tailwind v4).
Aplícalas por defecto al crear/ajustar vistas. Se resuelven **en el design system**
cuando el patrón es transversal (para que Cotejo/Pulse/PIVAS lo hereden) y en la
vista solo lo específico.

## Tablas y listados
- **Móvil (≤768px): tabla → tarjetas** apiladas (una fila = una tarjeta). El
  nombre de columna sale de `data-label` por celda (`data_table` ya lo hace).
- **Cabecera de tarjeta**: la primera fila se muestra como banda con fondo
  (`--surface-alt`); **sin líneas** entre datos.
- **Acciones**: en móvil van en un **menú ⋮** anclado arriba a la derecha de la
  tarjeta (`mobile_actions_menu` en `data_table`), no una fila de acciones vacía.
  No usar íconos con tooltip en táctil (no hay hover). Con 1–2 acciones, botones
  de texto de ancho igual; con 3+, menú.
- **Filtros**: en móvil a dos columnas (`.filter-grid`); paginador a la derecha y
  duplicado al pie.

## Detalle (patrón claim_live/show)
- **Stepper de estado** arriba (ruta del ciclo de vida; estado actual resaltado,
  terminal en rojo).
- **Header**: estado a la derecha como *pill* de color sólido (visible); acciones
  en un menú `ui-menu` (details). Notificaciones (p. ej. videollamada) **debajo**
  del header.
- **Dos columnas** en desktop: datos (izquierda) + tabs (derecha), del mismo ancho;
  se apilan en ≤900px. Contenedor centrado con `max-width` (`.page-container` en el
  layout aplica a todas las vistas).
- **Tabs** para agrupar (Evidencia / Grabación / Conversación / Auditoría); que no
  hagan scroll (envuelven, padding reducido).
- **Datos**: campos tipo caja (etiqueta en MAYÚSCULAS arriba, valor abajo), celdas
  uniformes; sin líneas entre datos.

## Modales
- Header con fondo (`--surface-alt`) y esquinas superiores redondeadas.
- **Línea separadora antes de los botones** del footer (incluso si el footer va
  dentro del body con estilo inline).
- Tamaño fijo con `max-height: 90vh` + scroll para no exceder la pantalla.

## Gotchas
- **Especificidad CSS**: `.admin-table td { position: relative }` gana a
  `.admin-table-actions--menu`. Para posicionar el menú hay que **calificar con
  `td.`** (`td.admin-table-actions--menu`).
- **overflow**: no poner `overflow:hidden` en la tarjeta si adentro hay un menú
  desplegable (lo recorta).
- **Mapas** sin API key: iframe de OpenStreetMap embed centrado en las coordenadas.

## Semántica de dominio
- La **firma del asegurado es conformidad/aceptación**, NO evidencia: va en su
  propia tarjeta ("Conformidad del asegurado"), con sello de integridad (SHA-256)
  y evento en auditoría; no dentro de la evidencia.

## Verificación
- Compilar la lib con `mix compile --warnings-as-errors` y correr tests antes de
  dar por hecho un cambio. Lo visual (móvil real) lo confirma el usuario en el
  navegador.
