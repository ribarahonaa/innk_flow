# Handoff

## Objetivo

Tres trabajos en una sesión, en este orden:

1. **Los cuatro puntos del handoff anterior** (botón de guía de IA, «Listo» en
   propuestas informativas, la cuenta de demo que mentía, la captura del camino
   `_top`). Mergeados y ya documentados en el handoff de `95a42f9`.
2. **El 404 contra 403.** Empezó como corregir una línea de `CLAUDE.md` y la
   auditoría encontró oráculos de existencia en ideas, comentarios, propuestas,
   corridas y membresías, y **dos fugas de lectura**: un gestor leía los
   criterios de desafíos que no le asignaron, y quien perdía la membresía con
   la sesión abierta seguía listando todos los desafíos. Rama `doc-404-403`,
   mergeada por Raúl.
3. **El plan 2a del rediseño**: el vocabulario visual que se repite pasa a
   componentes de DaisyUI —tarjetas, tablas, avisos, chips, nodos del flujo—,
   con una guarda de contraste nueva en `make screens`. Spec, plan y ejecución
   con subagentes (implementador y revisor por tarea, revisión final de rama
   entera). Rama `rediseno-2a`, mergeada.

## Estado actual

- **`master` en `0269b31`**, igual que `origin/master`. Sin ramas locales
  además de `master`.
- **Verificación sobre `0269b31`:** `make spec` 880 ejemplos, 0 fallas.
  `make screens` 42 capturas sin errores, y sin ninguna guarda disparada
  (`[CLASES]`, `[CONTRASTE]`, `[PANEL]`, `[RITMO]`).
- **Ramas remotas ya mergeadas que siguen en `origin`:** `doc-404-403` y
  `rediseno-2a`. No se borraron: las pusheó Raúl.
- **Queda en `.superpowers/sdd/2026-09-08-rediseno-tailwind-fase-1/`** el
  espacio de trabajo de la fase 1, de otra sesión. El del 2a se borró al
  terminar; su registro de decisiones está resumido abajo.
- **Hechos del entorno que muerden:**
  - El push por SSH no anda; va por HTTPS con el token de `gh`:
    `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/ribarahonaa/innk_flow.git <ref>`.
  - Desarrollo usa el proveedor real (`FLOW_AI_PROVIDER=anthropic`); el de
    embeddings es el fixture, por eso «Detectar duplicados» es gratis.
  - **El contenedor `app` no recompila CSS ni JS solo:** después de tocar la
    hoja, un `.vue` o una clase literal en un helper, `make yarn-build` antes
    de `make screens`, o las capturas prueban la hoja vieja.

## Archivos y cambios

**El 404 contra 403 (`doc-404-403`, 13 commits)**

- Ideas, comentarios, propuestas de IA, corridas y membresías se buscan por
  `policy_scope` o por visibilidad antes de autorizar: lo que no se ve da 404.
  `CLAUDE.md` decía «404, nunca 403», y el código nunca hizo eso: el 403 es
  correcto para lo que se ve y no se puede hacer.
- `ApplicationPolicy::Scope#resolve` devuelve `none` sin membresía.
- `CriteriaSetPolicy::Scope`: la biblioteca, a la vista de la empresa; cada set
  `inline`, a la de su desafío.
- `AiSuggestionPolicy#visible?`: le aparece en un panel **y** ve aquello sobre
  lo que actúa. `AssessmentPolicy#create?` pregunta si se llega al desafío, con
  el primer spec de policy directo del repo.
- Una evaluación de IA no se edita antes de aplicarla
  (`Tasks::EvaluateIdea#editable?`).
- `spec/lint/ideas_por_policy_scope_spec.rb`: guarda que prueba su propio
  detector y lista en su comentario lo que no ve.

**Plan 2a (`rediseno-2a`, 17 commits)**

- `docs/superpowers/specs/2026-09-16-rediseno-2a-vocabulario-design.md` y
  `docs/superpowers/plans/2026-09-16-rediseno-2a-vocabulario.md`.
- `.card` → `.panel`, y `card` de DaisyUI habilitada; guarda `[PANEL]` contra
  un `card` sin `card-body`.
- `step-table` → `table`; `step-table__link` → `table-link`.
- Avisos → `alert alert-soft`, incluidos 7 en islas Vue.
- Chips (estado, origen, tipo de feedback, IA) → `badge badge-soft` vía
  `EstilosHelper`; nace `chip_de_ia`. Nodos del flujo → `badge`.
- **Guarda de contraste en `make screens`:** medidor con autoprueba (grises,
  color puro y opacidad), medición en cada pantalla, **muestrario** de cada
  variante inyectado y medido en claro y en oscuro, y un spec que ata el
  muestrario al helper.
- Los comentarios atendidos y las rondas cerradas **dejaron de usar
  `opacity`**: dejaba sus chips en 3:1. Ahora pesan menos sin leerse peor.
- `CLAUDE.md`: cuatro trampas nuevas en «Lo que más fácil se rompe».
- ~70 líneas de CSS muerto borradas.

## Intentos fallidos

- **La regla de visibilidad de las propuestas se escribió cuatro veces.**
  `accept?` a secas convertía en 404 el 403 legítimo de quien administra un
  desafío cerrado. «Se ve si se ve su objetivo» le dejaba 403 a quien participa
  por una propuesta del flujo. `manager? || accept?` **reabrió una escritura**:
  un gestor dado de baja con la asignación intacta aplicaba una evaluación
  sobre un desafío que le daba 404. La encontró la re-revisión con un probe;
  la cuarta combina las dos mitades.
- **La auditoría del 403 descartó el oráculo de membresías** con que «las
  membresías no son secretas»; lo que no se ve es el id. Y **la fuga de quien
  perdió la membresía no la encontró la auditoría: la encontró la revisión.**
- **La guarda de lint se evadió dos veces**, y probar su detector encontró dos
  bugs: `#.*\z` no llega al final con el `\n` de `readlines`, y sacar
  `.ideas.new(` sin dejar un espacio pegaba `@challengeIdea`.
- **Un `private` en medio de `class << self` se llevó puesto `.for`**, y un
  `begin/rescue/end` en HAML (no acepta `- end`): 50 specs en rojo cada uno.
- **El plan 2a traía defectos míos que corrigieron las revisiones:**
  - las capturas navegan por clases que el plan renombraba, y la Tarea 2 colgó
    `make screens`;
  - los valores de prueba del medidor eran todos grises y no podían detectar
    pesos de canal invertidos;
  - el medidor ignoraba la opacidad de los ancestros;
  - **la pasada oscura midió cero avisos y dio verde**: sus cuatro pantallas no
    tienen ninguno. De ahí nació el muestrario;
  - la guarda del muestrario buscaba cada clase en el archivo entero, no en el
    arreglo.
- **La Tarea 5 rompió dos cosas que ninguna guarda veía**: los puntos de estado
  del drawer y el borde por tipo de feedback, las dos por reglas CSS que usaban
  las clases viejas desde afuera de su bloque. Las encontré leyendo, no
  corriendo nada.
- **El nodo de un módulo salteado quedó negro** (`badge-dash` sin variante) y
  pasó a ser el más pesado del mapa. Ningún seed tiene un módulo salteado, y el
  17,5:1 que midió el muestrario era el síntoma. Lo encontró la revisión final.

## Próximos pasos

1. **Plan 2b** (pantalla por pantalla), escrito recién ahora que 2a está
   mergeado. Lo que ya se sabe que le toca:
   - pasar `.panel` a `card` + `card-body`; la guarda `[PANEL]` ya lo admite;
   - seis familias de chip escritas a mano (`version-chip`, `stale-chip`,
     `here-chip`, `out-chip`, `evaluator-chip`, `derived-chip`) que la guarda
     de contraste no mide;
   - una captura permanente del estado salteado del flujo, sin romper el seed
     `sin-formulario`;
   - desacoplar del color del `badge` el borde por tipo de feedback
     (`data-kind`) y el selector de los puntos del drawer;
   - `toast`, si se quiere.
2. **Plan 2c:** las islas Vue.
3. **Tres temas de seguridad preexistentes, sin arreglar**, que son cambios de
   flujo y no de visibilidad:
   - la sesión de quien perdió la membresía sigue viva: esto cerró lo que ve,
     no la puerta (`require_company` no pide membresía);
   - los links de los adjuntos (Active Storage) no vencen y quedan fuera de
     Pundit;
   - se puede asignar a evaluar a alguien con rol `participant` por POST
     directo, y dar de baja a alguien deja sus asignaciones.
4. Borrar del remoto `doc-404-403` y `rediseno-2a`, si se quiere.

**Decisiones del plan 2a que quedaron tomadas** (las 21 están en los mensajes
de commit y la revisión final las dio por buenas); las que cambian lo que se ve
o condicionan al 2b:

- Los comentarios atendidos se ven menos desvaídos que antes: sin opacidad,
  contorno punteado y texto en gris. Reversible.
- `master` se integró a mitad del plan por merge y no por rebase, para no
  reescribir los commits del registro.
- El estado salteado se verificó con una captura temporal y no con un seed
  nuevo.
