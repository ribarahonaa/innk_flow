// Lo que la mesa teclea en la sala se guarda solo, para que un refresh no se lo
// lleve. NO publica nada: el borrador vive en `workshop_drafts` y mandarlo sigue
// siendo apretar el botón.
//
// El ciclo de vida es el mismo par que `arrival_live.js` e `islands.js`
// —`turbo:load` para arrancar, `turbo:before-render` para limpiar—: un
// mecanismo, no tres. Sin el limpiado, navegar a otra pantalla deja un
// temporizador pidiendo contra una pantalla que ya no está.
//
// Sin `setInterval`, a diferencia de `arrival_live.js`: ahí el dato cambia en el
// servidor y hay que ir a buscarlo; acá cambia en el navegador y lo que hace
// falta es esperar a que pare de cambiar.
let timer = null;
let form = null;
let sucio = false;
// El pedido en vuelo, para cancelarlo si sale uno más nuevo.
let enVuelo = null;

// Sólo hay timeouts acá, nunca un interval: `alTeclear` reinicia la espera en
// cada tecla. Un `clearInterval` haría creer que hay un ciclo que no existe.
function stop() {
  if (timer === null) return;
  clearTimeout(timer);
  timer = null;
}

function sello() {
  return document.getElementById('draft-stamp');
}

// El cuerpo se arma a mano y NO con `new FormData(form)`: un FormData crudo
// incluye el `<input type=file>`, así que subiría el archivo elegido cada dos
// segundos. Un borrador no guarda archivos —y un file input no sobrevive una
// recarga en ningún navegador—.
//
// Y recorre TODOS los campos, no sólo el que cambió: no es derroche, es la
// condición para que el prellenado no borre nada. El servidor reemplaza el hash
// del borrador entero, sin merge; si un PATCH mandara un solo campo, al recargar
// los demás volverían en blanco, y mandar eso publicaría el vacío. No lo
// «optimices» a un diff.
function cuerpo(form) {
  const datos = new URLSearchParams();
  const idea = form.dataset.draftIdea;
  if (idea) datos.append('idea_id', idea);
  for (const campo of form.querySelectorAll('[name^="payload["]')) {
    if (campo.type === 'file') continue;
    if ((campo.type === 'checkbox' || campo.type === 'radio') && !campo.checked) continue;
    if (campo.multiple && campo.tagName === 'SELECT') {
      for (const opcion of campo.selectedOptions) datos.append(campo.name, opcion.value);
      continue;
    }
    datos.append(campo.name, campo.value);
  }
  return datos;
}

async function guardar({ keepalive = false } = {}) {
  if (!form || !sucio) return;
  sucio = false;
  // Dos PATCH solapados con wifi lento pueden llegar al revés y dejar el
  // borrador con texto que la mesa ya había borrado. Abortar el anterior achica
  // esa ventana y NO la cierra: si el servidor ya recibió el viejo, cancelar del
  // lado del cliente no lo deshace. El orden fuerte pediría un número de
  // secuencia en el servidor, que para «el último que escribe gana» no se
  // justifica.
  //
  // Un pedido `keepalive` ni aborta ni se registra: es el de despedida de
  // `descargar()`, y si quedara en `enVuelo` el primer guardado de la pantalla
  // siguiente cancelaría justo lo que no se podía perder. No hay nadie después
  // que lo reemplace.
  const control = new AbortController();
  if (!keepalive) {
    if (enVuelo) enVuelo.abort();
    enVuelo = control;
  }
  // El formulario desde el que salió el pedido: la respuesta puede llegar con
  // otra pantalla ya pintada, y el acuse no es de ahí.
  const enviadoDesde = form;
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  try {
    const res = await fetch(enviadoDesde.dataset.draftUrl, {
      method: 'PATCH',
      headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: cuerpo(enviadoDesde),
      keepalive,
      signal: control.signal
    });
    // Un fallo se DICE, no se traga. Un autoguardado que falla en silencio es
    // peor que no tenerlo: la mesa confía y pierde todo.
    if (!res.ok) throw new Error(res.status);
    if (form !== enviadoDesde) return;
    // «0» es un 204 de «no había nada que guardar»: no es un fallo, pero decir
    // «Guardado» sería mentir. Tras un fallo previo el «No se pudo guardar» se
    // queda a propósito: no se guardó nada, y el autoguardado está roto de verdad.
    if (res.headers.get('X-Draft-Saved') === '0') return;
    const s = sello();
    if (s) s.textContent = s.dataset.savedText;
  } catch (err) {
    // Lo cancelamos nosotros por uno más nuevo: no es un fallo, y escribir el
    // texto de error sería contradecir al pedido que lo reemplazó.
    if (err.name === 'AbortError') return;
    if (form !== enviadoDesde) return;
    // El fallo se dice y se REINTENTA en la tecla siguiente: un parpadeo de wifi
    // no apaga el autoguardado el resto de la tarde. El texto de fallo se queda
    // en el sello hasta que un guardado exitoso lo reemplace. Nada de
    // `form = null`: el listener cuelga del nodo y no de esta variable.
    // Sin `stop()` a propósito: a esta altura el temporizador que dispararía
    // este guardado ya venció, y uno vivo sería de una tecla MÁS NUEVA que no hay
    // por qué cancelar.
    const s = sello();
    if (s) s.textContent = s.dataset.failedText;
  } finally {
    if (enVuelo === control) enVuelo = null;
  }
}

function alTeclear() {
  sucio = true;
  stop();
  timer = setTimeout(guardar, Number(form.dataset.debounce) || 2000);
}

function start() {
  const encontrado = document.querySelector('form[data-draft-url]');
  // Turbo 8 morfea: después de un POST que vuelve a la misma URL el NODO del
  // formulario es el mismo y `turbo:load` corre de nuevo. Si es el mismo nodo ya
  // está cableado, y además puede tener un guardado pendiente: pararlo acá lo
  // cancelaría sin reprogramarlo hasta la tecla siguiente.
  if (encontrado && encontrado === form) return;
  // El nodo cambió (o no hay formulario): el temporizador del anterior se para.
  stop();
  form = encontrado;
  if (!form) return;
  form.addEventListener('input', alTeclear);
  // Mandar es publicar: el borrador lo borra el servidor en la misma
  // transacción, así que un guardado en vuelo no tiene que pisarlo después.
  //
  // NO cubre el envío FALLIDO: los caminos de rechazo redirigen con un `alert:`
  // (302 → 200), así que `turbo:submit-end` da `success: true` igual y no hay
  // cómo distinguirlos del exitoso. Ahí el morph devuelve el valor del servidor
  // y se pierde lo tecleado desde la última pausa de dos segundos. Se acepta:
  // guardar siempre recrearía, tras cada envío exitoso, el borrador que el
  // servidor acaba de borrar, y la sala volvería prellenada con lo ya mandado.
  form.addEventListener('submit', () => { sucio = false; stop(); });
}

// Este camino NO lo mide ninguna guarda ni ningún spec: la guarda espera el
// debounce, así que el temporizador normal ya guardó. Borrar `descargar()`, el
// `keepalive` y el `visibilitychange` no pone nada en rojo.
//
// Irse de la pantalla no puede llevarse los últimos dos segundos. `keepalive`
// deja el pedido en vuelo aunque el documento se vaya.
function descargar() {
  stop();
  guardar({ keepalive: true });
}

addEventListener('turbo:load', start);
addEventListener('turbo:before-render', descargar);
addEventListener('visibilitychange', () => { if (document.hidden) descargar(); });
