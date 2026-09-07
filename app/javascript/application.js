// Chrome compartido. Las islas Vue NO se importan acá: cada una es su propio
// pack (app/javascript/packs/*.js) y la vista que la necesita la incluye.
import '@hotwired/turbo-rails';

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
