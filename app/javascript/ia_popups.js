// Los dos popups de la IA: el de esperar y el de responder.
//
// Pedirle algo a la IA tiene dos momentos y ninguno se veía. Mientras piensa
// —de 10 a 70 segundos con un proveedor real— el único aviso era una franja
// dentro del marco de propuestas: no bloqueaba nada, se podía navegar a otra
// pantalla con el pedido en vuelo, y ni siquiera existía en los pedidos que
// responden a la pantalla entera. Cuando respondía, el mensaje viajaba en el
// flash que el layout pinta AFUERA del marco, así que Turbo lo descartaba.
//
// El servidor deja la respuesta en un `<template data-ia-respuesta>` —dentro
// del marco y en el layout, ver `shared/_ia_respuesta`— y acá se arman los
// popups a partir de los eventos de Turbo.
//
// LOS DIÁLOGOS LOS ARMA EL JS Y NUNCA EXISTEN DURANTE UN RENDER. El layout
// declara `turbo-refresh-method: morph`: un `<dialog open>` que el cliente
// agregó y el servidor no manda es un nodo de más, y idiomorph se lo lleva
// puesto a mitad de camino —o peor, le saca el `open` y deja el popup en el
// DOM sin verse—. Por eso el de espera se cierra y se saca en
// `turbo:before-render`, y el de respuesta se arma recién después de pintar.
//
// Las clases van escritas ENTERAS y literales: Tailwind escanea
// `app/javascript` igual que las vistas, y una clase armada con interpolación
// no llega a la hoja. El elemento queda sin ninguna regla detrás y en el DOM
// se ve perfecto mientras en pantalla no se ve nada.

const ENDPOINT = '/ai_requests';

let espera = null;
let respuesta = null;

// El único endpoint que hace pensar a la IA de forma síncrona. Un solo
// listener cubre TODOS los botones —las acciones del panel, «Mejorar con IA»,
// el «IA» de la evaluación, «Pedir la guía de la IA»— sin tocar ninguno.
function esPedidoDeIa(form) {
  if (!(form instanceof HTMLFormElement)) return false;
  try {
    return new URL(form.action, location.href).pathname.endsWith(ENDPOINT);
  } catch {
    return false;
  }
}

function nuevoDialogo(cual) {
  const el = document.createElement('dialog');
  el.className = 'modal';
  el.dataset.ia = cual;
  return el;
}

// Irse de la página con un pedido en vuelo pierde la respuesta que ya se está
// pagando. El navegador pide confirmación; Chrome ignora el texto y muestra
// el suyo, y `returnValue` es lo que todavía exigen los demás.
function avisarAntesDeSalir(e) {
  e.preventDefault();
  e.returnValue = '';
}

function abrirEspera() {
  if (espera) return;

  espera = nuevoDialogo('espera');
  espera.setAttribute('aria-labelledby', 'ia-espera-titulo');
  espera.innerHTML = `
    <div class="modal-box ia-espera" role="status" aria-live="polite" aria-busy="true">
      <span class="loading loading-spinner loading-lg ia-espera__spinner"></span>
      <h2 class="section-title" id="ia-espera-titulo">La IA está pensando</h2>
      <p class="muted">Puede tardar un minuto. No cierres ni recargues la página.</p>
    </div>
  `;
  // No se puede cerrar: `cancel` es Escape, no hay botón de cerrar, y no se
  // agrega `modal-backdrop` —que es el form que DaisyUI usa para el clic
  // afuera—, así que un clic afuera no hace nada.
  espera.addEventListener('cancel', (e) => e.preventDefault());

  document.body.appendChild(espera);
  espera.showModal(); // deja el resto de la página inerte: ni clics ni Tab.
  addEventListener('beforeunload', avisarAntesDeSalir);
}

function cerrarEspera() {
  removeEventListener('beforeunload', avisarAntesDeSalir);
  if (!espera) return;
  espera.close();
  espera.remove();
  espera = null;
}

function cerrarRespuesta() {
  if (!respuesta) return;
  respuesta.close();
  respuesta.remove();
  respuesta = null;
}

// El cuerpo puede venir de un `<template>` del servidor o armado acá (los
// errores que el servidor nunca llegó a contar).
function abrirRespuesta(cuerpo, tipo) {
  cerrarEspera();
  cerrarRespuesta();

  respuesta = nuevoDialogo('respuesta');
  respuesta.setAttribute('aria-labelledby', 'ia-respuesta-titulo');

  const caja = document.createElement('div');
  caja.className = tipo === 'error' ? 'modal-box ia-respuesta ia-respuesta--error' : 'modal-box ia-respuesta';

  const cerrar = document.createElement('button');
  cerrar.type = 'button';
  cerrar.className = 'btn btn-sm btn-circle btn-ghost ia-respuesta__cerrar';
  cerrar.setAttribute('aria-label', 'Cerrar');
  cerrar.textContent = '✕';
  cerrar.addEventListener('click', cerrarRespuesta);

  caja.append(cerrar, cuerpo);

  // El clic afuera. Es el `modal-backdrop` de DaisyUI: un form con un botón
  // que ocupa lo que queda del diálogo.
  const fondo = document.createElement('form');
  fondo.method = 'dialog';
  fondo.className = 'modal-backdrop';
  fondo.innerHTML = '<button aria-label="Cerrar">cerrar</button>';

  respuesta.append(caja, fondo);
  // Escape y el clic afuera cierran el `<dialog>` pero no lo sacan del DOM, y
  // un nodo de más sobrevive hasta el próximo morph.
  respuesta.addEventListener('close', () => { respuesta?.remove(); respuesta = null; });

  document.body.appendChild(respuesta);
  respuesta.showModal();
}

function mensajeSuelto(texto, extra) {
  const cuerpo = document.createElement('div');
  const titulo = document.createElement('h2');
  titulo.className = 'section-title';
  titulo.id = 'ia-respuesta-titulo';
  titulo.textContent = 'La IA no pudo';
  const parrafo = document.createElement('p');
  parrafo.className = 'ia-respuesta__mensaje';
  parrafo.textContent = texto;
  cuerpo.append(titulo, parrafo);
  if (extra) cuerpo.append(extra);
  return cuerpo;
}

// Después de pintar: si el servidor dejó una respuesta, se abre. Los templates
// se borran TODOS —llegan hasta dos, el del marco y el del layout— para que la
// próxima navegación no vuelva a abrir lo mismo.
function mostrarLoQueDejoElServidor() {
  const plantillas = document.querySelectorAll('template[data-ia-respuesta]');
  if (!plantillas.length) return;

  const primera = plantillas[0];
  const cuerpo = primera.content.cloneNode(true);
  const tipo = primera.dataset.tipo;
  plantillas.forEach((t) => t.remove());

  abrirRespuesta(cuerpo, tipo);
}

// ── Los eventos de Turbo ────────────────────────────────────────────────────

addEventListener('turbo:submit-start', (e) => {
  if (esPedidoDeIa(e.target)) {
    abrirEspera();
    return;
  }
  // Aplicar y Descartar salen del popup con `data-turbo-frame: "_top"`: se
  // cierra acá, antes de que el morph llegue y se encuentre el diálogo puesto.
  if (respuesta && respuesta.contains(e.target)) cerrarRespuesta();
});

// Red de seguridad: ningún camino puede dejar la espera abierta. Sólo cuando
// NO hubo éxito —si lo hubo, la cierra `turbo:before-render` justo antes de
// pintar, que es cuando corresponde: cerrarla acá deja la pantalla vieja
// interactiva unos milisegundos antes de que llegue la nueva.
addEventListener('turbo:submit-end', (e) => { if (!e.detail?.success) cerrarEspera(); });

// Justo antes de pintar, en los dos caminos: el marco y la pantalla entera.
addEventListener('turbo:before-frame-render', cerrarEspera);
addEventListener('turbo:before-render', () => { cerrarEspera(); cerrarRespuesta(); });

// Después de pintar, en los tres caminos: marco, morph/render y carga normal.
addEventListener('turbo:frame-render', mostrarLoQueDejoElServidor);
addEventListener('turbo:render', mostrarLoQueDejoElServidor);
addEventListener('turbo:load', mostrarLoQueDejoElServidor);

// Se cayó la red: el servidor no contestó nada, así que el mensaje lo arma el
// cliente. Sin esto la espera queda girando para siempre.
addEventListener('turbo:fetch-request-error', () => {
  abrirRespuesta(mensajeSuelto('No se pudo hablar con el servidor. Revisá tu conexión y probá de nuevo.'), 'error');
});

// La respuesta no trae el marco que se pidió: un 403, un 500, o la sesión
// vencida que devuelve el login. Turbo escribiría «Content missing» adentro
// del marco y nada más.
addEventListener('turbo:frame-missing', (e) => {
  e.preventDefault();
  const recargar = document.createElement('button');
  recargar.type = 'button';
  recargar.className = 'btn btn-primary btn-sm';
  recargar.textContent = 'Recargar la página';
  // Sin el aviso de salida de por medio: recargar acá es lo que pedimos.
  recargar.addEventListener('click', () => { removeEventListener('beforeunload', avisarAntesDeSalir); location.reload(); });
  abrirRespuesta(mensajeSuelto('La respuesta no llegó como se esperaba.', recargar), 'error');
});

// Volver atrás no puede mostrar un popup viejo: los diálogos no entran al
// caché de Turbo.
addEventListener('turbo:before-cache', () => { cerrarEspera(); cerrarRespuesta(); });
