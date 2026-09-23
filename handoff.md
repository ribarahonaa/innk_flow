# Handoff

## Objetivo

Dos cosas: dejar la base con sólo los desafíos del seed, y abrir el rol
`gestor` para que administre los desafíos que le asignaron.

Lo segundo se ejecutó con `superpowers:subagent-driven-development`: spec de
diseño, plan de seis tareas, un subagente fresco por tarea, revisión por tarea
con dos veredictos, y una revisión de rama entera en Opus al final.

## Estado actual

- **`master` está en `a6aa59e` y pusheado.** Verificado contra el remoto con
  `gh api`, no con `git rev-parse origin/master` —que lee una foto local—. Sin
  ramas vivas.
- **`make spec` → 1092 ejemplos, 0 fallas** (venía de 1017), corrido sobre el
  resultado del merge y no sólo sobre la rama. **`make screens` → 66 capturas,
  0 errores.**
- **La base quedó limpia**: 9 desafíos, todos del seed. Los hechos a mano se
  borraron y el respaldo se eliminó, por decisión de Raúl. El stack quedó
  levantado.
- **El 400 del proveedor real se resolvió** (lo confirmó Raúl desde la app), así
  que el punto 1 del handoff anterior está cerrado.

### El push va por HTTPS, y hay una forma limpia de hacerlo

El remoto es SSH y en este entorno no autentica. Lo que funciona **sin tocar la
config global ni exponer el token en la línea de comandos**:

```bash
git -c credential.helper='!gh auth git-credential' \
    push https://github.com/ribarahonaa/innk_flow.git master
```

## Archivos y cambios

### El rol gestor (merge `a6aa59e`, 18 commits)

`ApplicationPolicy#administra?(challenge)` es la regla nueva y vive una sola
vez: `manager? || (membership.present? && membership.gestor? &&
reaches_challenge?(challenge))`. Generaliza la expresión que `curate_pool?` ya
tenía escrita a mano —la única puerta que el gestor tenía hasta ahora—.

**Se aplicó puerta por puerta y no tocando `manages_challenges?`.** Ese atajo
—un carácter de diff— abría membresías, auditoría de IA y biblioteca a todo
gestor de la empresa sin acotar por desafío. Con el predicado explícito, las
tres puertas que quedan cerradas se quedan **porque nadie las tocó**, y eso se
lee en el diff.

Se abrieron 18 puertas por-desafío en seis policies. `configure?` y pedirle
cosas a la IA sobre el desafío se abrieron **solos**, por delegación.
**Ninguna vista hubo que tocar para eso**: los 45 usos de permisos en HAML
preguntan por `policy(...)`, que es donde CLAUDE.md manda que viva la guarda.

Dos huecos que el cambio abría, cerrados acá: el editor de criterios se
renderiza por `configure?` pero guardaba por `CriteriaSetPolicy` (el gestor
veía el editor y no podía guardar), y crear un desafío sin auto-asignarse lo
sacaba de la lista de su propio creador en el mismo movimiento.

**`administra?` tiene una redundancia aparente que es load-bearing.**
`manager? || reaches_challenge?(challenge)` NO es equivalente: abriría todo
para `participant` y `evaluator`, por la rama `return true unless gestor?` de
`reaches_challenge?`. Está comentado en el código; no lo "limpies".

### Lo que encontró la revisión final, y ninguna revisión por tarea podía ver

Las tres estaban en **vistas**, porque la spec dijo «no se toca ninguna vista
salvo la del botón de promover» y eso fue un punto ciego de la spec:

- **Las dos pantallas donde se otorga el acceso describían el rol al revés.**
  `_gestores.html.haml` decía «No evalúan ni configuran» y `es.yml` decía
  «Acompaña la evolución». Las dos eran ciertas antes y pasaron a ser falsas.
  Son los dos únicos lugares donde una persona decide entregar este poder.
- **Dos links con 403 garantizado** («Ver el set», «Editar el set»): gateaban
  por `update_pipeline?` y su destino exige `manager?`. El principio del
  arreglo: **la guarda de un link pregunta lo mismo que autoriza su destino**.
- **`create?` abierto sin entrada en la UI**: los dos únicos
  `new_challenge_path` colgaban de `manages_challenges?`.

## Intentos fallidos

**El patrón de la ejecución: los dos únicos hallazgos serios fueron agujeros de
cobertura, no bugs de código.** Ninguna tarea escribió una policy mal. Tiene
sentido para este cambio —abrir un permiso de más no rompe ningún test,
simplemente deja pasar—, así que el riesgo nunca estuvo en el código sino en si
la red existía. Las dos veces el brief que los originó lo había escrito yo.

- **Una fila sin su control de admin** (`IdeaPolicy#destroy?`) pasaba igual con
  la policy rota. Resultó que **ningún test de la suite cubría que un admin
  pueda borrar una idea**.
- **Nada fijaba la polaridad del botón de promover**: un `unless` en vez del
  `if` pasaba la suite entera en silencio. Es el mismo modo de falla que
  `dos_caras_spec.rb:264-267` documenta para la guarda de afuera.

**De ahí salió la práctica que más sirvió: romper la guarda a mano y confirmar
que el test falla.** En las tareas 3 y 5 el resultado fue el necesario —fallaron
sólo los ejemplos nuevos, el resto de la suite quedó verde con el código
roto—, lo que prueba dos cosas de una: que la cobertura nueva sirve y que el
agujero anterior era real.

**Un hook de seguridad bloqueó esa prueba una vez** (`[Security Weaken]`, al
intentar debilitar `configure?`). El subagente no insistió por otra vía y yo
tampoco lo hice desde otra silla. Consecuencia: la cobertura de `configure?`
es la única sostenida sólo por lectura de código.

**Errores míos de esta sesión:**

- **Afirmé que el gestor podría borrar el desafío** y no existe ruta de borrado:
  `resources :challenges, only: %i[index new create show]`. `ChallengePolicy#update?`
  y `#destroy?` son código muerto.
- **Commiteé la spec y el plan directo a `master`** y hubo que moverlos a una
  rama. La convención es rama por tanda.
- **Le puse línea `Co-Authored-By` al primer commit**, contra la regla.
- **La spec excluyó las vistas**, que es de donde salieron los tres hallazgos
  de la revisión final.
- **Conté mal las puertas** («~15» cuando son 18) en un borrador de la spec.

## Próximos pasos

1. **Los menores diferidos del rol gestor**, ninguno bloqueante:
   - Una variable local muerta (`- desafio = step.challenge`) en
     `_referencia_evaluacion.html.haml:8`, que quedó sin uso al arreglar el
     link. Trivial.
   - `AssessmentPolicy#update?` cambió de contrato sin cobertura; hoy no tiene
     llamador vivo en `app/`.
   - Sin cobertura de `CriteriaSetPolicy#update?` con `owner_step: nil`. No se
     alcanza por la app (la FK es `ON DELETE CASCADE`) y **falla cerrado**.
   - «Ver el set» de `_referencia_evaluacion` usa el mismo predicado que su
     hermano pero no tiene test de polaridad propio.
   - La tabla de `gestor_administra_spec.rb` no tiene columna de `participant`
     ni `evaluator`. Seguro por la forma del predicado; tres líneas si se
     quiere la red.

2. **Dos preexistentes que merecen rama propia**, los dos confirmados esta
   sesión:
   - **`CriteriaSetPolicy::Scope` achica sólo para el gestor**, así que un
     participante abre **por id** un set `inline` de un desafío que no ve
     (`show?` heredado = `membership.present?`). El índice no lo lista —filtra
     a biblioteca—, así que la fuga es por id, no por listado.
   - **El breadcrumb de `criteria_sets/edit.html.haml`** siempre enlaza a
     `criteria_sets_path`, que sólo lista biblioteca: para un set `inline` la
     vuelta va a una lista que nunca lo muestra.

3. **Lo que sigue abierto de handoffs anteriores:**
   - **Las 57 capturas que nunca se miraron**, y los seis defectos anotados de
     las 9 que sí (drawer que no llega al fondo, botones apilados en «Acción»,
     `select` sin flecha, los 15 avisos indistinguibles, la tarjeta de testing
     que se repite, el popup de IA redundante).
   - **`Pipeline#validate` vs `Selection#can_activate?`**: una selección de
     sólo filtros no arranca el flujo salvo que se le declare el puntaje
     manual. Hay tres lugares documentando el mismo rodeo. Merece issue propio.
   - **Las once FKs con `ON DELETE SET NULL` sin acotador.** El helper ya está
     arreglado, las viejas no.
   - **`[FORMS]` no cubre las pantallas de formulario a las que se llega por
     clic.**
   - **Cuatro menores del módulo de testing**, diferidos con triage.
   - **Plan 2c** (el resto de las islas Vue), `SelectionsController#update` sin
     validación server-side, `criteria_sets#show` huérfana, las 3 consultas de
     evolución, los tres temas de seguridad preexistentes, y que nada vigila el
     relleno por default de `card` desde que se retiró `[CARD]`.

## Decisiones de Raúl en esta sesión

- **Limpiar la base dejando sólo los desafíos del seed**, y **borrar el
  respaldo** con los hechos a mano.
- **Gestor = admin en sus desafíos**, y no el punto medio ni el cambio acotado
  a testear.
- **De las puertas que no cuelgan de un desafío, sólo se abre crear desafíos**:
  membresías, auditoría de IA y biblioteca de criterios siguen siendo de admin.
- **Equivalencia completa**: la apertura pisa las dos reglas que acotaban al
  gestor (editar una idea sólo con la ronda abierta, evaluar sólo con
  asignación). Quedan las dos exclusiones por conflicto de interés, que son de
  otro eje.
- **Ejecutar el plan por subagentes**, no inline.
- **Mergear a master y pushear.**
