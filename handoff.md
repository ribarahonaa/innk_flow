# Handoff

## 1. Objetivo

Documentar qué hace innk_flow y cómo lo hace, en dos capas: deep-dives técnicos
versionados en `docs/` para quien va a tocar el código, y una explicación de
producto como página compartible para dev + stakeholder.

## 2. Estado actual

**Terminado.** Nada pendiente del alcance acordado.

Los cinco huecos que `docs/` no cubría ya tienen archivo propio, el README
quedó al día y la capa de producto está publicada como documento.

Lo que **no** se tocó, a propósito: `CLAUDE.md` (sigue siendo el registro de
trampas), los cuatro deep-dives previos (`ai`, `criteria`, `pipeline`,
`tenancy`) y los 18 specs/plans de `docs/superpowers/`.

**No se commiteó nada.** El árbol tiene los seis archivos sin commitear.

## 3. Archivos y cambios

| Archivo | Qué es |
|---|---|
| `docs/orientacion.md` | **Nuevo** (230 líneas). El primer día: qué leer en qué orden, el mapa del código, cómo verificar, cuatro recetas (agregar un kind, una tarea de IA, un criterio automático, una pantalla) |
| `docs/datos.md` | **Nuevo** (267). Las 34 tablas de dominio por subsistema, las cuatro invariantes del esquema, lo que Postgres hace valer y Ruby no |
| `docs/taller.md` | **Nuevo** (673). El deep-dive que faltaba: ciclo de vida, abrir, cierre perezoso, mesas, reparto, check-in, la sala, borrador, grabación, permisos, seed |
| `docs/permisos.md` | **Nuevo** (446). Los cuatro roles, los tres predicados base, lo que no vive en el rol, la regla 404-vs-403, las doce policies |
| `docs/frontend.md` | **Nuevo** (716). Turbo morph, las cuatro islas, las tres capas de CSS, el layout, y qué ve y qué NO ve cada guarda de `make screens` |
| `README.md` | **Modificado**. Puntero a `orientacion.md`, sección nueva del taller, índice de los diez documentos, y el renglón de roles corregido |

Lo que el README decía mal y ahora no: «`gestor` acompaña la evolución». Hoy
**administra los desafíos que le asignaron**, que es otra cosa. Y no mencionaba
el taller en ninguna parte.

**Documento de producto** (fuera del repo, privado hasta que se comparta):
https://claude.ai/code/artifact/e15fff0d-cadd-464b-a29b-6a28d7ce63e9
Ocho secciones más un diagrama del flujo con la línea de agua.

## 4. Intentos fallidos

**No falló nada que haya que no repetir.** La sesión fue de escritura, no de
depuración. Lo que sí hubo fueron cinco correcciones de conteo, todas por
medir en vez de copiar de `CLAUDE.md`, y vale anotar el método:

- «29 modelos» → **34** (36 archivos en `app/models` menos `application_record`
  y `current`, que no son AR).
- «39 tablas» → **34 de dominio** (39 `CREATE TABLE` menos las tres de Active
  Storage, `schema_migrations` y `ar_internal_metadata`).
- «70 FKs compuestas» se confirmó, pero el primer grep daba **101** porque
  contaba también los 31 `company_id → companies`. El patrón que discrimina es
  `FOREIGN KEY \([a-z_]+, company_id\)`.
- «diez pantallas» con el panel de propuestas de IA → **once lugares**: nueve
  pantallas más los dos editores embebidos.
- «42 guardas» en `make screens`: son **43 marcadores** en el archivo, pero
  `[CARD]` sobrevive sólo en un comentario. Y el primer grep se perdió
  `[ESTADO-DRAWER]` porque el patrón no incluía el guion.

La lección, que es la misma que el repo ya documenta: **un número copiado de
prosa envejece sin avisar.** Donde se pudo, el documento dice cómo verificarlo
(un grep) en vez de dar el número.

## 5. Próximos pasos

1. **Leer los cinco documentos nuevos y corregir lo que esté mal.** Están
   escritos contra el código, pero hay juicios de énfasis que son discutibles.
2. **Commitear.** Nada está en git todavía:
   ```
   git add README.md docs/orientacion.md docs/datos.md docs/taller.md \
           docs/permisos.md docs/frontend.md handoff.md
   ```
   Mensaje sugerido: «Documentar los cinco huecos: orientación, datos, taller,
   permisos y frontend; el README los indexa y corrige el renglón del gestor».
3. **Compartir el documento de producto** desde el menú Share, si va a leerlo
   alguien más: hoy es privado y el link no abre para nadie.
4. **Decidir si `CLAUDE.md` adelgaza.** Varias de sus secciones ahora tienen un
   deep-dive propio —el taller sobre todo— y podría quedarse sólo con lo que es
   trampa pura, remitiendo al resto. **No se hizo porque no estaba en el
   alcance** y porque `CLAUDE.md` es lo que se carga en contexto cada sesión:
   recortarlo es una decisión con consecuencias, no prolijidad.
