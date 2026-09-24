# Handoff

## Objetivo

La primera de las tres inconsistencias sistémicas que dejó el repaso de las 66
capturas: **el estado del dominio se dibujaba de tres formas distintas**. Al
terminar se dibuja de una —el chip—, el chip se ve como chip sobre cualquier
superficie, y hay una guarda que lo mide en las 66 pantallas y en los dos
temas.

## Estado actual

- **`master` está en `5edac9b` y quedan 6 commits SIN pushear.** El remoto
  sigue en `30f5f8a`, verificado con `gh api` y no con `git rev-parse
  origin/master`, que lee una foto local. Sin ramas vivas, árbol limpio.
- **`make spec` → 1118 ejemplos, 0 fallas** (venía de 1115) y **`make screens`
  → 66 capturas, 0 errores**. Las dos corridas sobre el resultado del merge, no
  sólo sobre la rama.
- El stack quedó levantado. La base no se tocó.

### El push, que en este entorno no es obvio

El remoto es SSH y acá no autentica. Sin tocar la config global ni exponer el
token en la línea de comandos:

```bash
git -c credential.helper='!gh auth git-credential' \
    push https://github.com/ribarahonaa/innk_flow.git master
```

### Decisiones de Raúl en esta sesión

- Arrancar por el estado dibujado de tres formas, que era por la que el handoff
  anterior recomendaba arrancar.
- El arreglo de la pastilla **alcanza a todo `badge-soft`**, no sólo a los chips
  de estado: una sola regla en la hoja que heredan las seis familias.
- «Cómo le fue» pasa a **chip con familia propia**, y el borde izquierdo de 3px
  se va.
- **«Quedó afuera» va en ámbar**, no en rojo: que una idea no avance es el
  resultado normal de un filtro, no un error. `CHIP_DE_ESTADO` sigue sin
  variante de error.
- Del diseño: la variante C —componer contra la superficie real MÁS una guarda
  que hace innecesaria la lista de superficies—.
- Ejecución nativa, no por subagentes, con una revisión de rama al final.
- Merge a master local, sin PR.

## Archivos y cambios

Diseño en `docs/superpowers/specs/2026-09-24-el-estado-se-dibuja-de-una-forma-design.md`
y plan en `docs/superpowers/plans/2026-09-24-el-estado-se-dibuja-de-una-forma.md`.
Merge `5edac9b`.

### `98129db` — La pastilla se ve sobre cualquier superficie

`badge-soft` de DaisyUI mezcla fondo y borde contra `--color-base-100` —o sea
contra **blanco**— y no contra la superficie real. Ahora se derivan de
`currentColor` con alfa, así que se componen sobre el fondo real por
construcción y **no hay lista de superficies que mantener a mano**.

**Una sola regla y no seis por variante**: `currentColor` resuelve al color con
el que el chip termina pintando —incluidos `--ok`, `--warn` y `--danger`, los
tokens oscurecidos del texto—, así que una variante nueva no se puede olvidar.

**Relleno 4%, borde 30%.** El que define la pastilla es el **borde**: el texto
se apoya en el relleno, y subirlo hasta que se viera dejaba el texto en 3,92:1
sobre base-200 en claro. Con este par no hubo que retocar ningún token de
texto.

Guarda `[PASTILLA]` en `capturar()` —o sea en las 66 pantallas y en los dos
temas—, que mide **lo más fuerte del relleno y el borde** contra el fondo
compuesto. Piso 1,25:1, sacado del chip neutro de hoy (1,201). Con autotest de
seis casos.

### `817ce87` — «Cómo le fue» dice el estado con un chip

`CLASE_DE_RESULTADO` → `CHIP_DE_RESULTADO`. `done` va al neutro y no al verde
—es lo que decía el borde de 3px, y así el verde queda significando «avanzó»—,
`eliminated` va ámbar. Se fueron `.result--*` y el `border-left-width: 3px`.

### `484853a` — La ronda de feedback cerrada se pinta con su propio estado

Estaba escrita a mano con el color de `skipped` y la etiqueta del estado real:
una ronda completada salía **ámbar diciendo «completado»**.

### `511e29d` — La guarda cubre lo que decía cubrir

Los dos Important de la revisión de rama. Ver «Intentos fallidos».

## Intentos fallidos

**El hallazgo más caro de la sesión es de la revisión, y es sobre una guarda
que yo había escrito y declarado probada.**

- **Uno de los seis casos del autotest NO discriminaba la mutación que tenía
  asignada.** El caso «atenuado a la mitad» ponía el grupo atenuado sobre
  blanco con superficie transparente, así que atenuar blanco sobre blanco daba
  blanco: medía **1,1447 con y sin** las dos líneas que existía para proteger.
  Lo verifiqué antes de aceptarlo y era exacto. Es la guarda-que-siempre-pasa
  que `capture_screens.js` declara dos veces que hay que evitar, escrita en el
  archivo que la declara. **Un autotest con el valor esperado correcto no
  prueba que el caso discrimine: hay que mutar el código y ver que falla.** Con
  la superficie de adentro opaca y distinta mide 1,251 bien y 1,895 mutado.
- **El muestrario no medía pastilla, sólo contraste.** Existe precisamente
  porque el recorrido no garantiza mostrar cada variante en cada tema —la
  pasada oscura son diez pantallas—, y encima sus muestras atenuadas se
  inyectan dentro de `.feedback-round--cerrada .feedback-item`, que es la
  superficie base-200 **donde vivía el bug**. Era el mejor banco del script y
  estaba sin usar.

**Y el handoff anterior se equivocaba en una de las tres formas.** Decía «texto
de color sin badge en el builder con el flujo arrancado». No existe: es un
`badge` con la clase correcta —`PipelinePresenter` la manda hecha con el mismo
`chip_de_estado` que el HAML— cuya pastilla medía 1,02:1. **El problema no era
una vista que se olvidó el chip, era el chip.** Medirlo antes de escribir nada
cambió el arreglo entero.

**Y era MUCHO más grande de lo que el spec decía.** El spec describía la
pastilla invisible sobre superficies base-200. La guarda encontró que estaba
débil en **52 de las 66 pantallas**, tarjetas blancas incluidas: con el 8% de
tinte de fábrica el único chip que se leía como pastilla era el neutro, y sólo
porque `base-content` es oscuro.

**Tres defectos del plan que aparecieron al ejecutarlo**, los tres anotados
como rulings:

- El `grep` de «nada quedó colgando» no excluía `app/assets/builds/`, así que
  matcheaba el bundle compilado —que tiene las reglas viejas hasta
  `make yarn-build`— y daba un falso positivo enorme.
- El plan esperaba 1116 ejemplos al cerrar y son 1118. La cuenta estaba mal, no
  la suite.
- `task-start` de la skill busca encabezados `Task N` y acá el plan los escribe
  `Tarea N`, porque la documentación va en español. Se leyeron las secciones
  directo en vez de renombrarlas para contentar al script.

**Lo que funcionó:** medir antes de diseñar. Los porcentajes, el piso y hasta
la elección de mecanismo salieron de correr Playwright contra la app real —54
chips, siete pantallas, dos temas— y no de razonar sobre la hoja. La primera
propuesta (enumerar las superficies base-200 y declararles `--color-base-100`)
se cayó sola en cuanto la medición mostró que eran ocho y que una nueva
reintroduciría el bug en silencio.

## Próximos pasos

1. **Pushear `master`**: 6 commits (ver el comando arriba).

2. **Las otras dos inconsistencias sistémicas**, que siguen abiertas:
   - **Monospace para prosa y para números:** «veredicto por idea», «pasó su
     prueba de factibilidad, con reservas o sin ellas», los pesos (40%, 25%),
     las claves de criterio. Es lo que hace parecer volcado de debug a «Cómo
     quedó configurado».
   - **«N de M · ahora: X» se lee como posición y no lo es:** en `04` dice
     «6 de 7 · ahora: Reporte de cierre», que es el módulo 7. Cuenta módulos
     terminados o salteados. Misma familia que el «3 / 2». Ojo: la cabecera del
     drawer muestra el estado del desafío como **texto plano sin chip** en esa
     misma línea —una cuarta forma de dibujar estado— y se dejó a propósito
     para esta tanda.

3. **Los minors diferidos de la revisión de rama**, ninguno urgente:
   - `[PASTILLA]` no asegura «midió al menos N» por pantalla: si los chips
     dejaran de llamarse `badge`, mediría cero y pasaría. Lo tapan el spec de
     Ruby «todos los chips son badge» y el conteo del muestrario.
   - La regla nueva **debilita `[CLASES]` para los chips suaves**: el término
     «sin fondo» ya no puede ser verdadero para un `badge-soft`. Compensado por
     `[PASTILLA]`, que caza el mismo escenario.
   - Un **borde punteado se acredita como pastilla entera** (el nodo salteado
     del mapa del flujo).
   - `flow.entry_statuses.skipped` quedó **huérfano** en `es.yml`: no es un
     `StepEntry::STATUSES`. Es previo a esta rama.
   - Los números del comentario de la hoja (1,53 / 1,59 / 4,85 / 4,63) salen de
     54 chips en **7** pantallas, no de las 66, y el comentario no lo acota.
   - `medirContraste` corre **dos veces por pantalla** sobre `.badge`
     (`revisarContraste` y `revisarPastilla`). Una sola medición compartida
     ahorraría la mitad.
   - **`.alert` sigue con el 8% de relleno de DaisyUI.** Se lee porque es una
     caja grande con borde propio, pero es la misma línea. Extender `[PASTILLA]`
     a `.alert` es cambiar un selector.

4. **Lo visual que sigue en pie del repaso de capturas:** `Choose File / No file
   chosen` sin estilo en `16-idea-new`; `18-select-company` con el rol fuera del
   botón y el separador colgando; el popup de espera sin backdrop
   (`09-13-ia-espera`); la previsualización que se repite a sí misma en 5 de 7
   tarjetas; el popup de la IA que dice lo mismo tres veces; el desglose con
   claves en vez de nombres; el hueco muerto del Brief; «Cómo quedó
   configurado» encabalgado; la columna «Acción» que apila; «Armar el flujo con
   IA» sin controles con el flujo arrancado; «Distribución de puntajes» con dos
   filas de números; «Quién evalúa» duplicado sin el peso.

5. **Los menores diferidos del rol gestor** (variable muerta en
   `_referencia_evaluacion.html.haml:8`, `AssessmentPolicy#update?` sin
   cobertura ni llamador vivo, `CriteriaSetPolicy#update?` con
   `owner_step: nil`, «Ver el set» sin test de polaridad, la tabla de
   `gestor_administra_spec.rb` sin columnas de `participant` ni `evaluator`) y
   **dos rastros del renombre dejados a propósito** (el nombre de
   `gestor_administra_spec.rb` y los documentos de `docs/superpowers/`).

6. **El backlog largo, intacto:** el breadcrumb de `criteria_sets/edit` que para
   un set `inline` vuelve a una lista que nunca lo muestra;
   `Pipeline#validate` vs `Selection#can_activate?`; las once FKs con
   `ON DELETE SET NULL` sin acotador; `[FORMS]` que no cubre las pantallas a
   las que se llega por clic; los cuatro menores del módulo de testing; el plan
   2c (el resto de las islas Vue), `SelectionsController#update` sin validación
   server-side, `criteria_sets#show` huérfana, las 3 consultas de evolución,
   los tres temas de seguridad preexistentes, y que nada vigila el relleno por
   default de `card` desde que se retiró `[CARD]`.

7. **Sobre el recorrido como red:** dos pares de capturas son la MISMA pantalla
   (`03c-paso-a-paso` = `09-10-form-vacio`, `05e-config-seleccion` =
   `09-12-criterios-del-modulo`), así que las 66 capturas no son 66 pantallas.
