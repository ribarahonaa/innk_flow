// La mesa de llegada se refresca sola mientras el check-in está abierto: quien
// proyecta el QR ve entrar gente sin tocar nada.
//
// Recarga un `turbo-frame` en vez de empujar por websocket. El porqué está en
// `docs/superpowers/specs/2026-10-02-lista-de-llegada-en-vivo-design.md`: la
// gema `turbo-rails` no está instalada, no hay un solo canal en la app, y el
// push pediría una conexión autenticada y scopeada por empresa en la parte que
// más se audita, para ganar unos segundos sobre gente que entra caminando.
//
// El ciclo de vida es el mismo par que usa `islands.js` —`turbo:load` para
// arrancar, `turbo:before-render` para limpiar—: un mecanismo, no dos. Sin el
// limpiado, navegar a otra pantalla deja un temporizador pidiendo contra una
// pantalla que ya no está.
let timer = null;

function detener() {
  if (timer === null) return;
  clearInterval(timer);
  timer = null;
}

function arrancar() {
  detener();
  const frame = document.getElementById('llegada');
  // `data-vivo` lo pone la VISTA: el JS no sabe ni tiene que saber si el taller
  // está abierto o el check-in encendido.
  if (!frame || frame.dataset.vivo !== 'true') return;
  // Con la pestaña oculta no se pide nada: una pantalla proyectada está
  // visible, una pestaña de fondo no tiene por qué consultar.
  if (document.hidden) return;

  const intervalo = Number(frame.dataset.intervalo) || 5000;
  timer = setInterval(() => {
    const vivo = document.getElementById('llegada');
    if (!vivo) return detener();
    vivo.reload();
  }, intervalo);
}

addEventListener('turbo:load', arrancar);
addEventListener('turbo:before-render', detener);
addEventListener('visibilitychange', () => (document.hidden ? detener() : arrancar()));
