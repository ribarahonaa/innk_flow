// Chrome compartido. Las islas Vue NO se importan acá: cada una es su propio
// pack (app/javascript/packs/*.js) y la vista que la necesita la incluye.
import '@hotwired/turbo-rails';
// Los dos popups de la IA: el de esperar y el de responder. Chrome compartido
// porque los botones de IA viven en diez pantallas.
import './ia_popups';

// Conservar el scroll cuando la pantalla se actualiza sin recargarse.
//
// El layout pide `turbo-refresh-scroll: preserve`, pero eso solo le dice a
// Turbo que NO scrollee él: no alcanza. El scroll se pierde antes, durante el
// morph — mientras idiomorph tiene nodos afuera del documento la página se
// acorta, el navegador recorta scrollY a lo que queda, y volver a meter los
// nodos no lo devuelve. Medido: `turbo:before-render` en 1083 y `turbo:morph`
// ya en 239, sin que Turbo hubiera scrolleado nada.
//
// Se guarda antes de renderizar y se devuelve después, y SOLO cuando hubo
// morph: en una navegación de verdad ir al tope es lo correcto.
(() => {
  let posicion = null;
  let morfeo = false;

  addEventListener('turbo:before-render', () => {
    posicion = window.scrollY;
    morfeo = false;
  });
  addEventListener('turbo:morph', () => { morfeo = true; });
  addEventListener('turbo:render', () => {
    if (!morfeo || posicion === null) return;
    // En una constante y no en la variable: el rAF corre DESPUÉS, y para
    // entonces `posicion` ya volvió a null —scrollTo(0, null) es scrollTo(0, 0)
    // y el bug se ve igual que no haber hecho nada—.
    const destino = posicion;
    posicion = null;
    // Después del layout: si la pantalla se acortó, el navegador recorta al
    // tope, que es lo que corresponde.
    requestAnimationFrame(() => window.scrollTo(0, destino));
  });
})();

// Un plegable abierto sigue abierto cuando la pantalla se actualiza.
//
// El `open` de un <details> lo pone quien lo abre, en el cliente. Un POST que
// redirige a la misma URL morfea contra el HTML del servidor, que no lo trae,
// e idiomorph lo saca: guardar un peso adentro de «Ajustes del módulo» cerraba
// los ajustes en la cara de quien acababa de guardar. Se cancela solo la
// REMOCIÓN: un `open` que agrega el servidor sigue entrando.
addEventListener('turbo:before-morph-attribute', (event) => {
  const { attributeName, mutationType } = event.detail;
  if (event.target instanceof HTMLDetailsElement && attributeName === 'open' && mutationType === 'remove') {
    event.preventDefault();
  }
});
