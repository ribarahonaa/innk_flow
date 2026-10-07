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
function cuerpo() {
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
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  try {
    const res = await fetch(form.dataset.draftUrl, {
      method: 'PATCH',
      headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: cuerpo(),
      keepalive
    });
    // Un fallo se DICE, no se traga. Un autoguardado que falla en silencio es
    // peor que no tenerlo: la mesa confía y pierde todo.
    if (!res.ok) throw new Error(res.status);
    const s = sello();
    if (s) s.textContent = s.dataset.savedText;
  } catch {
    const s = sello();
    if (s) s.textContent = s.dataset.failedText;
    stop();
    form = null;
  }
}

function alTeclear() {
  sucio = true;
  stop();
  timer = setTimeout(guardar, Number(form.dataset.debounce) || 2000);
}

function start() {
  stop();
  const encontrado = document.querySelector('form[data-draft-url]');
  // Turbo 8 morfea: después de un POST que vuelve a la misma URL el NODO del
  // formulario es el mismo y `turbo:load` corre de nuevo. Sin esta comparación
  // cada navegación suma un listener más sobre el mismo elemento.
  if (encontrado && encontrado === form) return;
  form = encontrado;
  if (!form) return;
  form.addEventListener('input', alTeclear);
  // Mandar es publicar: el borrador lo borra el servidor en la misma
  // transacción, así que un guardado en vuelo no tiene que pisarlo después.
  form.addEventListener('submit', () => { sucio = false; stop(); });
}

// Irse de la pantalla no puede llevarse los últimos dos segundos. `keepalive`
// deja el pedido en vuelo aunque el documento se vaya.
function descargar() {
  stop();
  guardar({ keepalive: true });
}

addEventListener('turbo:load', start);
addEventListener('turbo:before-render', descargar);
addEventListener('visibilitychange', () => { if (document.hidden) descargar(); });
