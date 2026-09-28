# Handoff

## Objetivo

Ordenar lo pendiente por prioridad y cerrar los dos P0 que salieron de ese
orden: las dos FKs compuestas `ON DELETE SET NULL` sin acotar y los archivos que
se servían por fuera de Pundit.

Los dos están cerrados, mergeados y pusheados. Cada uno pasó por revisión de
rama, y las dos revisiones encontraron cosas reales.

**El listado vive en una página con estado propio, no en un archivo:**
https://claude.ai/artifact/C2i3g3ZRz1gUeMuX3bEXrq — 57 tareas tildables en 19
frentes, cinco tramos de prioridad, y los checks se guardan solos. P0 quedó
`6 / 6`.

## Estado actual

- **Dos merges: `37bb173` (las FKs) y `2bff3e2` (los archivos). La punta de
  `master` es el commit de este handoff.** Pusheado, sin ramas vivas ni locales
  ni en el remoto, árbol limpio.
- **`make spec` → 1169 ejemplos, 0 fallas** (venía de 1151) y **`make screens`
  → 66 capturas, 0 errores**.
- El árbol de cada merge es idéntico al de su rama.
- El stack quedó levantado, con la app reiniciada (el cambio de
  `config/application.rb` no se recarga en caliente).
- **La base de desarrollo se tocó tres veces y a propósito:** `db:migrate`, una
  ida y vuelta `db:rollback` + `db:migrate` para probar el `down`, y `db:seed`
  para probar que la restricción nueva no rompe el seed. Todas las mediciones
  destructivas —los `DELETE` que probaban el bug— fueron dentro de una
  transacción con `ROLLBACK`.

### Decisiones de Raúl en esta sesión

1. **El listado como página con checks**, no como `docs/backlog.md`: «saber
   cuáles vamos terminando de forma más simple».
2. **Cerrar el hallazgo del set de criterios en la misma rama de las FKs**, en
   vez de dejarlo como ítem propio.
3. **Borrar del remoto la rama ya mergeada**, condicionado a que estuviera
   pasada (lo verifiqué antes: era ancestro de master con cero commits propios).
4. **Para los archivos: cerrar las rutas de Active Storage** (y no sólo dejar de
   usarlas) **y `send_data`**, sabiendo que carga el archivo en memoria.
5. «Avisame cuando termine» sobre el P0-2: autonomía de punta a punta, revisión
   y merge incluidos.

## Archivos y cambios

**`37bb173` — las dos FKs.** Tres commits: `1fb0f56` (la migración y el
acotador), `49d7985` (el set en uso no se borra), `12189e6` (lo que encontró la
revisión).

`ON DELETE SET NULL` sobre una FK compuesta nulea TODAS las columnas si no se
acota con `SET NULL (columna)`. Dos de las catorce no lo tenían, así que borrar
un criterio o un run de IA moría con `PG::NotNullViolation`. El acotador se sumó
a `add_tenant_fk` DESPUÉS de que esa migración corriera, y las dos viejas
quedaron mal en la base y en el dump — o sea en todo entorno nuevo y en
`innk_flow_test`.

La guarda pasó de cubrir 1 de 14 a leer el catálogo, con la regla escrita como
**«nulear no puede romper un NOT NULL»** en vez de «no puede nombrar
company_id»: cubre cualquier otra columna NOT NULL y también acotar la columna
equivocada. Y tiene **piso**: sin él, una consulta rota devuelve cero filas y el
ejemplo pasa midiendo nada.

De ahí salió el segundo commit: sin el `NotNullViolation` accidental, borrar un
set de criterios en uso pasaba a funcionar, y eso se lleva sus criterios — de
donde el snapshot congelado de un módulo arrancado resuelve las escalas por id.
Va como `restrict_with_error` en la asociación.

**`2bff3e2` — los archivos.** Dos commits: `03b7a49` (las dos acciones y el
cierre de rutas), `4c6c821` (lo que encontró la revisión).

`IdeaAttachmentsController#show` y `ReportsController#download`, cada uno detrás
de la puerta que ya existía, y `draw_routes = false`. Entregar el archivo va por
`ApplicationController#send_attached_file`, que concentra la guarda de
`attached?`, el `content_type_for_serving` y el `disposition`.

## Intentos fallidos

### Una guarda que no funcionaba por el ORDEN de declaración

La primera versión del «set en uso no se borra» era un `before_destroy` propio y
**daba verde con el defecto adentro**: el callback que agrega
`dependent: :nullify` corre ANTES de uno declarado más abajo, así que preguntaba
`in_use?` cuando los steps ya estaban vaciados y contestaba que no. No se ve
leyendo la guarda; se ve en el orden de las líneas. Expresar la regla COMO la
asociación (`restrict_with_error`) borra la pregunta del orden en vez de
esquivarla.

### Perdí trabajo con `git checkout --`

Para sacar una mutación de prueba corrí `git checkout -- spec/tenancy/schema_spec.rb`
sobre un archivo que tenía el rewrite de la guarda **sin commitear**. Se fue
entero. Lo noté porque la medición siguiente imprimió el mensaje de la versión
vieja, no el nuevo — o sea que estuve midiendo la guarda vieja creyendo que era
la nueva. **Para sacar una mutación de un archivo con trabajo sin commitear, el
reemplazo puntual (sed/python), nunca `git checkout --`.**

### Dos afirmaciones mías que había que corregir

- **El hunk de `pg_dump` no se puede limpiar.** Dije que re-dumpear sacaría el
  reformateo incidental de los CHECK. Re-dumpeé: el ruido se **mueve** a otros
  tres CHECK. Es no determinista entre corridas, así que se queda el dump
  original y no hay nada que perseguir.
- **Eran TRES call sites de `rails_blob_path`, no dos.** El tercero es el JSON
  del polling de reportes. Sin él, el endpoint tiraba 500 en cuanto las rutas se
  cerraran.

### Dos ejemplos míos que pasaban por el motivo equivocado

- **«Sin sesión no entrega el archivo» corría CON sesión.** El `let!` sube el
  adjunto firmando como la autora. Lo cazó al fallar; va con `reset!`. Y la
  revisión sumó que afirmar «cualquier cosa menos 200» también pasaría si la
  autenticación desapareciera y el pedido cayera en un 404 por scope: ahora
  afirma `redirect_to(login_path)`.
- **El `link_to` de descargas no lo renderizaba NINGÚN spec.** El único reporte
  `ready` de la suite es un `dashboard` sin archivo, así que la condición
  `ready? && attached?` nunca se cumplía y un helper mal escrito daba verde con
  500 en pantalla.

### Lo que encontraron las revisiones, y que yo no

- **La guarda nueva podía pasar midiendo cero** (sin el piso).
- **El aviso del borrado mentía**: las aserciones miraban el dato y no la
  respuesta, así que un `destroy` sin `if` decía «Set eliminado.» con el set
  todavía en la lista.
- **Un archivo no adjunto era 500 y no 404**, alcanzable por todo reporte
  `dashboard` (nace `ready` sin archivo) y por una fila de adjunto sin archivo.
- **Un comentario afirmaba lo contrario del código** en un archivo que el diff
  tocó («el link de Active Storage no pasa por Pundit»).
- **`\bIdea\b` no matchea `IdeaAttachment`**, así que el lint de ideas no vería
  el bug que este controller existe para no tener. Está anotado en su lista.

### Una acusación mía equivocada, otra vez

`origin/fk-set-null-acotadas` apareció en el remoto sin que yo la pushée, y me
puse a buscar hooks y a greppear el transcript del revisor. **La había pusheado
Raúl.** Antes de investigar de quién fue algo en el remoto, preguntar.

## Lo que funcionó

**Verificar cada hallazgo de la revisión antes de implementarlo.** Las dos
Important de la primera revisión eran afirmaciones sobre mutaciones que
sobreviven, así que se comprueban CORRIENDO la mutación: las dos sobrevivían.
Las dos de la segunda eran un 500 alcanzable, así que se comprueba escribiendo
el ejemplo y viéndolo fallar con `ArgumentError`. Ninguna se implementó a ciegas.

**Mutar la base de test para medir un detector de esquema.** Desacotar de verdad
una constraint y volverla a acotar es lo único que prueba que el detector mide el
catálogo y no su propia opinión.

**Pedirle al revisor las preguntas que me preocupaban**, no sólo el diff. La
pregunta «¿queda algún camino sin autenticar a un archivo?» devolvió un barrido
de trece superficies que yo no había mirado (el file server estático, los
mailers, los jobs, las variantes, el layout del PDF, el disk service).

## Cosas del entorno

- **El remote está por SSH y acá no hay clave.** Todo lo que sale a la red va con
  la URL HTTPS explícita: `git push https://github.com/ribarahonaa/innk_flow.git
  master`. `git remote prune origin` y `git push origin` fallan. De rebote, el
  ref de seguimiento queda viejo después de pushear y hay que moverlo a mano
  (`git update-ref refs/remotes/origin/master`), o `git status` dice «ahead N»
  sobre algo ya pusheado.
- **La suite falló una vez con `PG::ConnectionBad: Connection refused`** (4
  fallas, la base se cayó a mitad de corrida). En aislamiento esos ejemplos dan
  0 fallas y la corrida siguiente dio 1169/0. Si aparecen fallas raras y
  agrupadas, mirar si el contenedor de la base se reinició antes de leer el
  diff.
- El harness sigue inyectando `Co-Authored-By` por system-reminder; hay que
  cortarla a mano. En los cinco commits no quedó.
- `docker compose restart app` hace falta después de tocar `config/`.

## Próximos pasos

El orden completo está en la página del listado. Lo inmediato:

1. **P1, cinco frentes:** `[FORMS]` que no cubre las pantallas a las que se
   llega por clic (es la guarda que `CLAUDE.md` nombra por el bug del corte, o
   sea ciega justo donde ya mordió); que nada vigile el relleno por default de
   `card` desde que se retiró `[CARD]`; asignar a evaluar a un `participant` por
   POST directo (y que dar de baja a alguien le deje las asignaciones vivas); la
   sesión que sobrevive a perder la membresía; y el aviso del corte que infla el
   número con un id fabricado.

2. **P2, cinco decisiones tuyas**, ninguna es trabajo pendiente:
   - **La línea en `CLAUDE.md`** sobre la convención del nombre en `activate!`.
     Sigue sin hacerse por lo mismo que la vez pasada: la pidió un subagente.
     **Y ahora hay una segunda candidata**: que las rutas de Active Storage
     están cerradas y un `has_one_attached` nuevo necesita su propia acción. Lo
     documenté en `docs/tenancy.md`, que es un doc y no `CLAUDE.md`; si querés
     una línea en la sección de multi-tenancy, es tuya.
   - `docs/pipeline.md` desactualizado en dos puntos.
   - Los dos controles que no existen en ninguna vista (saltear un módulo,
     cerrar un desafío).
   - **Para qué existe `DELETE /criteria_sets/:id`**: el modelo ya se niega si
     el set está en uso, así que la capacidad es sana; falta decidir si se
     muestra un control (deshabilitado con el motivo, y ahí es donde el aviso
     tendría que nombrar QUÉ módulo lo usa) o si se saca la ruta. El precedente
     de `CLAUDE.md` corta hacia sacarla: `Tasks::EvaluateIdea#editable?` se
     borró por ser «una capacidad del dominio sin interfaz».
   - La concordancia del plural.

3. **Lo que las dos revisiones marcaron y no se tomó, con el motivo:**
   - Un ejemplo destructivo para las dos constraints arregladas: el piso las
     nombra, así que revertirlas ya falla.
   - Consolidar más allá de `send_attached_file`: con dos llamadores no rinde.
   - `ai_suggestions.criteria_set_id` es la única de sus cuatro columnas de
     destino **sin foreign key**, así que queda fuera de la garantía de FK
     compuesta. Dormida: hoy ninguna tarea apunta a un set. Está en el listado.
   - **Las guardas de esquema ven una FK equivocada pero no una FALTANTE**, así
     que nada detecta lo de arriba. En el listado.
   - `active_storage_blobs` y `active_storage_attachments` no tienen
     `company_id` ni FKs compuestas. Hoy es inocuo porque nada llega a un blob
     por id, y eso quedó escrito en `docs/tenancy.md`.
   - Sin CSP (`config/initializers/content_security_policy.rb` está comentado
     entero). Preexistente, y sólo pesaría si alguien sirviera un adjunto
     `inline`.

4. **Lo demás del listado**, sin cambios: los diez visuales del repaso de
   capturas, `.alert` con el 8% de relleno de DaisyUI (el más barato de todo:
   es extender `[PASTILLA]` a un selector), los cuatro del módulo de testing,
   los cinco del rol gestor, los cinco de la pastilla, el terreno ya medido y
   el backlog largo.
