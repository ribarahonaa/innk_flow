// La mesa graba su conversación.
//
// El estado vive ACÁ, en variables de módulo, y el DOM es una vista de él. Es
// lo que lo diferencia de sus dos hermanos, y copiarlos cortaría grabaciones:
//
//   · `arrival_live.js` PARA en `turbo:before-render`: un temporizador
//     apuntando a una pantalla muerta está mal.
//   · `workshop_draft.js` DESCARGA en `turbo:before-render`: los últimos dos
//     segundos no se pueden perder.
//   · esto no hace ninguna de las dos. `turbo:before-render` dispara también en
//     un morph, y un morph ocurre con cualquier POST que vuelva a la misma URL
//     —alguien de la mesa apretando «Crear borrador»—. Pararse ahí cortaría la
//     grabación de la reunión.
//
// Como el grabador y los trozos son de módulo, un morph que reemplaza el botón
// y el indicador no los toca: `turbo:load` vuelve a derivar el DOM, con la
// misma prueba de identidad de nodo que usa el borrador.
let caja = null;
let rec = null;
let trozos = [];
let stream = null;
let desde = null;
let cronometro = null;
// La onda. `audio` es el AudioContext, que hay que CERRAR al parar: sin eso
// queda uno por grabación y el navegador termina negándose a dar más.
let audio = null;
let analizador = null;
let muestras = null;
let frame = null;
// Subiendo: `rec` ya es null durante la subida, así que sin esta marca un
// repintado no distingue «subiendo» de «libre» y habilitaría el botón.
let subiendo = false;
// A DÓNDE va lo grabado, capturado al APRETAR GRABAR y no leído del DOM al
// parar. Parece redundancia y no lo es: `caja` se reasigna en `start()` en cada
// `turbo:load`, y ahí `caja = encontrado` pasa ANTES del `rec.stop()`, así que
// el handler de parada corría contra el contenedor de la pantalla NUEVA.
//
// El repro es de dos clics y no pide ninguna carrera: grabando en la sala A, al
// breadcrumb del taller (sin contenedor, así que `caja` queda en null, el bucle
// de dibujo se detiene y el grabador SIGUE, porque Turbo no dispara
// `pagehide`), «Entrar» a la sala B → `start()` encuentra un nodo nuevo →
// `rec.stop()` → la subida posteaba a `/recordings` de B, y el servidor
// resolvía la mesa de B: la conversación de la mesa A quedaba guardada como
// grabación de la mesa B, descargable por sus integrantes. La variante de un
// clic es en evolución: hacer clic en otra idea de la lista DETIENE la
// grabación, y la etiquetaba con la idea nueva, mientras la migración y la spec
// dicen que `idea_id` es «qué idea tenía la sala elegida AL APRETAR GRABAR».
//
// Con esto, «el estado vive en el módulo y el DOM es una vista» pasa a ser
// cierto también del destino, que es lo que cualquiera ya asume que significa.
let urlDeSubida = null;
let ideaDeSubida = null;

const TEXTOS = {
  start: 'Grabar',
  stop: 'Parar',
  uploading: 'Subiendo…',
};

// Cuántas barras hay NO se declara acá: el bucle lee `onda.children`, así que la
// cantidad vive en un solo lugar, el markup del partial. Una constante al lado
// sería una segunda fuente que el día que difiera deja barras sin dibujar o un
// índice fuera de rango.
//
// Abajo de esto la barra se dibuja en su mínimo. Es un umbral de PRESENTACIÓN y
// decide un alto en pixeles, no si se avisa algo: a diferencia del de la
// diarización, acá no hay decisión que un número inventado pueda falsear. El
// nivel CRUDO se publica igual en `data-level`, así que lo que se mide es la
// causa y no el dibujo.
const PISO_VISIBLE = 0.01;

function nodo(rol) {
  return caja ? caja.querySelector(`[data-recording-role="${rol}"]`) : null;
}

function pintar(estado, detalle = '') {
  const boton = nodo('toggle');
  const sello = nodo('status');
  if (!boton || !sello) return;

  if (estado === 'bloqueado') {
    boton.hidden = true;
    sello.textContent = detalle;
    return;
  }
  boton.hidden = false;
  boton.disabled = estado === 'subiendo';
  boton.textContent = estado === 'grabando' ? TEXTOS.stop : TEXTOS.start;
  sello.textContent = detalle;
}

// Por qué este navegador no puede grabar, o null si puede.
//
// `getUserMedia` NO EXISTE fuera de un contexto seguro, y `docker-compose`
// publica el puerto en plano: en la máquina que corre Docker es `localhost` y
// anda, y en el teléfono de al lado por `http://<ip>:3001` es `undefined`. Un
// botón que no hace nada es el control fantasma que este repo persigue, así que
// se pregunta ANTES de dibujarlo.
function impedimento() {
  if (!window.isSecureContext) return caja.dataset.insecureText;
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    return caja.dataset.insecureText;
  }
  if (typeof MediaRecorder === 'undefined') return caja.dataset.noDeviceText;
  return null;
}

function tictac() {
  if (!desde) return;
  const seg = Math.floor((Date.now() - desde) / 1000);
  const mm = String(Math.floor(seg / 60)).padStart(2, '0');
  const ss = String(seg % 60).padStart(2, '0');
  // Sólo el cronómetro: la onda que se mueve al lado ya dice «grabando».
  pintar('grabando', `${mm}:${ss}`);
}

// ── La onda ───────────────────────────────────────────────────────────────
//
// Barras del DOM y NO un `<canvas>`: no hay un solo canvas en el repo, y un
// canvas es una caja negra para todas las guardas —`[CLASES]`, `[CONTRASTE]`,
// `[SOMBRA]` no ven adentro— y una guarda que no puede ver DA PERMISO. De paso
// el color lo pone la hoja con `--dato`, en vez de que el JS tenga que leer el
// token y re-leerlo al cambiar de tema.
function abrirAnalizador() {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return false;
  audio = new Ctx();
  analizador = audio.createAnalyser();
  // 1024 en el dominio del tiempo alcanza de sobra para un RMS y cuesta menos
  // que el default de 2048.
  analizador.fftSize = 1024;
  muestras = new Uint8Array(analizador.fftSize);
  audio.createMediaStreamSource(stream).connect(analizador);
  return true;
}

// RMS de 0 a 1. Los bytes del dominio del tiempo vienen centrados en 128, así
// que el silencio da ~0 y no ~0,5.
function nivel() {
  if (!analizador) return 0;
  analizador.getByteTimeDomainData(muestras);
  let suma = 0;
  for (let i = 0; i < muestras.length; i++) {
    const v = (muestras[i] - 128) / 128;
    suma += v * v;
  }
  return Math.sqrt(suma / muestras.length);
}

function dibujar() {
  frame = null;
  if (!caja || !caja.isConnected) return;
  const onda = nodo('wave');
  // Se re-consulta cada frame y no se cachea: un morph puede haber reemplazado
  // las barras, y con la referencia vieja el bucle dibujaría sobre nodos
  // desconectados sin que se vea nada.
  if (!onda) return;

  const n = nivel();
  // El nivel CRUDO, que es lo que `[GRABAR]` mide. Tres decimales alcanzan y
  // evitan reescribir el atributo con ruido de punto flotante.
  caja.dataset.level = n.toFixed(3);

  const barras = onda.children;
  // Se corre todo una posición y la nueva entra al final: la onda SCROLLEA, que
  // es lo que deja ver dónde hubo silencio hace tres segundos. Un osciloscopio
  // instantáneo no muestra historia.
  for (let i = 0; i < barras.length - 1; i++) {
    barras[i].style.height = barras[i + 1].style.height;
  }
  const alto = n < PISO_VISIBLE ? 2 : Math.min(100, Math.round(n * 260));
  barras[barras.length - 1].style.height = `${alto}%`;

  if (rec && rec.state === 'recording') frame = requestAnimationFrame(dibujar);
}

function pararOnda() {
  if (frame !== null) cancelAnimationFrame(frame);
  frame = null;
  // CERRAR el contexto, no sólo soltarlo: uno por grabación se acumula.
  if (audio) audio.close().catch(() => {});
  audio = null;
  analizador = null;
  muestras = null;
  const onda = nodo('wave');
  if (onda) {
    onda.hidden = true;
    Array.from(onda.children).forEach((b) => { b.style.height = ''; });
  }
  if (caja) caja.dataset.level = '0';
}

// Mientras graba, irse de la página AVISA. No es prolijidad: `keepalive` tiene
// un tope de 64 KB por especificación y el audio son megabytes, así que una
// navegación real pierde lo grabado y no hay despedida que lo salve. Avisar es
// lo único que se puede hacer sin subida progresiva.
function alDescargar(e) {
  if (!rec || rec.state !== 'recording') return;
  e.preventDefault();
  // Los navegadores modernos ignoran el texto y muestran el suyo; hay que
  // asignar `returnValue` igual para que el diálogo aparezca.
  e.returnValue = '';
}

async function arrancar() {
  // El destino se LEE ACÁ, en el clic, y no en `subir()`: ver `urlDeSubida`
  // arriba. Al parar, `caja` puede ser el contenedor de otra sala.
  urlDeSubida = caja.dataset.recordingUrl;
  ideaDeSubida = caja.dataset.ideaId || null;

  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    trozos = [];
    // Bitrate EXPLÍCITO. Medido: el default de Chromium son 115 kbps, o sea
    // 17,4 MB por 20 minutos. Para transcribir, 32 kbps de opus alcanzan de
    // sobra y bajan eso a ~4,8 MB.
    const bits = Number(caja.dataset.bitrate) || 32000;
    // El constructor y el `start` van DENTRO del try, no al lado: los dos
    // pueden levantar (`NotSupportedError` por el mimeType, un
    // `InvalidStateError`), y afuera eso era una promesa rechazada sin manejar
    // —el micrófono quedaba abierto con su indicador prendido, el botón seguía
    // diciendo «Grabar» y nada pintaba un motivo—, que es exactamente el
    // control fantasma contra el que se escribió esta pantalla.
    rec = new MediaRecorder(stream, { audioBitsPerSecond: bits });
    rec.ondataavailable = (e) => { if (e.data && e.data.size) trozos.push(e.data); };
    rec.onstop = subir;
    rec.start(1000);
  } catch (e) {
    // Dos motivos distintos y dos textos distintos: qué hacer no es lo mismo.
    // Lo que levanta el constructor cae en la rama de «permiso denegado», que
    // no es preciso; es la misma imprecisión ya anotada para `NotReadableError`
    // y se acepta por lo mismo: pintar un motivo impreciso es mejor que no
    // pintar ninguno, y un texto nuevo es otra decisión.
    const texto = e && e.name === 'NotFoundError'
      ? caja.dataset.noDeviceText
      : caja.dataset.deniedText;
    // Soltar el micrófono: si lo que falló fue el grabador, `getUserMedia` ya
    // abrió el stream y sin esto queda tomado, con el indicador del navegador
    // prendido sobre una grabación que no existe.
    rec = null;
    soltarMicrofono();
    pintar('idle', texto);
    return;
  }
  desde = Date.now();
  cronometro = setInterval(tictac, 1000);
  tictac();

  // La onda arranca DESPUÉS del grabador: si el analizador no se puede abrir
  // —un navegador sin Web Audio— se graba igual. La onda es la mejor señal que
  // hay, no una condición para grabar.
  const onda = nodo('wave');
  if (abrirAnalizador() && onda) {
    onda.hidden = false;
    frame = requestAnimationFrame(dibujar);
  }
}

function soltarMicrofono() {
  pararOnda();
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
  if (cronometro !== null) clearInterval(cronometro);
  cronometro = null;
  desde = null;
  // El destino se limpia con el resto del estado de la grabación. `subir()` lo
  // copia a locales ANTES de llamar acá, así que la subida en vuelo no lo
  // pierde.
  urlDeSubida = null;
  ideaDeSubida = null;
}

async function subir() {
  // `urlDeSubida` y NO `caja.dataset.recordingUrl`: al parar, `caja` puede ser
  // el contenedor de OTRA sala —`start()` lo reasigna antes del `rec.stop()`—,
  // y postear ahí guarda la conversación de una mesa como grabación de otra.
  // Ver el comentario de `urlDeSubida`.
  const url = urlDeSubida;
  const idea = ideaDeSubida;
  const tipo = rec ? rec.mimeType : 'audio/webm';
  const blob = new Blob(trozos, { type: tipo });
  trozos = [];
  rec = null;
  soltarMicrofono();
  if (!url || !blob.size) { pintar('idle'); return; }

  subiendo = true;
  pintar('subiendo', TEXTOS.uploading);
  const cuerpo = new FormData();
  // La extensión sale del mimeType y no se fija a .webm: Safari da audio/mp4.
  const ext = tipo.includes('mp4') ? 'm4a' : 'webm';
  cuerpo.append('file', blob, `mesa.${ext}`);
  if (idea) cuerpo.append('idea_id', idea);

  try {
    const res = await fetch(url, {
      method: 'POST',
      body: cuerpo,
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '' },
    });
    // 201 y NO `res.ok`: un `before_action` que redirige —sesión caída,
    // membresía revocada— le llega al `fetch` como 200, porque el `fetch` sigue
    // el 302 y convierte el POST en GET. Es el mismo bug que el autoguardado
    // pagó, y acá costaría la reunión entera.
    if (res.status !== 201) { subiendo = false; pintar('idle', caja?.dataset.failedText); return; }
    // Se devuelve el botón a `idle` ANTES de navegar, y no es redundante: la
    // navegación es un morph a la misma URL, y `start()` en el mismo nodo
    // REPINTA desde el estado de módulo en vez de salir temprano, así que el
    // botón tiene que quedar coherente (libre, `subiendo` en false) antes de
    // visitar. Si no, el repintado lo dejaría en «subiendo» o con el texto del
    // servidor, y no habría quién lo corrija.
    subiendo = false;
    pintar('idle');
    // La pantalla la refresca el servidor: se visita la misma URL y Turbo
    // morfea, así que la tarjeta nueva aparece con su estado «en cola».
    window.Turbo ? window.Turbo.visit(window.location.href, { action: 'replace' })
                 : window.location.reload();
  } catch (_e) {
    subiendo = false;
    pintar('idle', caja?.dataset.failedText);
  }
}

function alApretar() {
  if (rec && rec.state === 'recording') { rec.stop(); return; }
  arrancar();
}

// La vista se deriva del estado de MÓDULO, nunca del DOM: después de un morph el
// DOM es el que mandó el servidor, o sea «Grabar» y el sello vacío.
function repintar() {
  if (rec && rec.state === 'recording') {
    // Sólo si el analizador existe: una onda plana sin analizador diría «el
    // micrófono no toma nada», que es una señal falsa y no una ausente.
    const onda = nodo('wave');
    if (onda && analizador) onda.hidden = false;
    tictac();
  } else if (subiendo) {
    pintar('subiendo', TEXTOS.uploading);
  } else {
    pintar('idle');
  }
}

function start() {
  const encontrado = document.querySelector('[data-recording-url]');
  // Turbo 8 morfea: después de un POST que vuelve a la misma URL el NODO puede
  // ser el mismo y `turbo:load` corre de nuevo. CABLEAR (sólo si el nodo
  // cambió: si no, el listener se duplica) y PINTAR (siempre, desde el estado)
  // son dos cosas distintas.
  const mismoNodo = encontrado && encontrado === caja;
  caja = encontrado;
  if (!caja) return;

  const boton = nodo('toggle');
  if (!boton) return;
  const motivo = impedimento();
  if (motivo) { pintar('bloqueado', motivo); return; }

  if (mismoNodo) {
    // No se recablea, pero SÍ se repinta: idiomorph comparó contra el HTML del
    // servidor y le devolvió al botón «Grabar» y al sello el vacío. Sin esto el
    // botón miente durante una grabación mientras la onda se sigue moviendo al
    // lado, y quien lo aprieta creyendo que arranca, para.
    repintar();
    return;
  }

  boton.addEventListener('click', alApretar);
  // Nodo nuevo por una navegación real: si venía grabando, el micrófono se
  // suelta, porque el estado anterior ya no tiene dónde mostrarse.
  if (rec && rec.state === 'recording') rec.stop(); else repintar();
}

addEventListener('turbo:load', start);
// Irse de la página de verdad sí para: el micrófono no puede quedar abierto.
addEventListener('pagehide', () => { if (rec && rec.state === 'recording') rec.stop(); });
addEventListener('beforeunload', alDescargar);
