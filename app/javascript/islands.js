// Montaje de islas Vue, compatible con Turbo.
//
// EL BUG QUE ESTO EVITA: con `DOMContentLoaded` a secas, una isla monta al
// entrar por URL directa pero NO al navegar por un link. Turbo intercepta el
// link, reemplaza el body por fetch y ese evento no vuelve a dispararse: la
// pantalla queda con el placeholder para siempre.
//
// Se cubren los tres momentos en que un pack puede empezar a correr:
//   · el DOM todavía carga        -> DOMContentLoaded
//   · Turbo navegó                -> turbo:load
//   · el script llegó tarde       -> montaje inmediato
//
// Y se desmonta antes de que Turbo cachee la página, para no guardar en la
// caché un DOM que Vue ya está manejando.
import { createApp } from 'vue';

export function mountIsland(name, component) {
  const selector = `[data-island="${name}"]`;

  function mountAll() {
    document.querySelectorAll(selector).forEach((el) => {
      if (el.__vueApp) return; // idempotente: turbo:load puede repetir

      let props = {};
      try {
        props = JSON.parse(el.dataset.props || '{}');
      } catch (error) {
        console.error(`[isla ${name}] props inválidas`, error);
        return;
      }

      el.innerHTML = '';
      const app = createApp(component, props);
      app.mount(el);
      el.__vueApp = app;
      // Señal explícita para los tests y para el script de capturas: esperar
      // contenido es adivinar, esperar esto es determinista.
      el.dataset.islandMounted = 'true';
    });
  }

  function unmountAll() {
    document.querySelectorAll(selector).forEach((el) => {
      if (!el.__vueApp) return;
      el.__vueApp.unmount();
      delete el.__vueApp;
      delete el.dataset.islandMounted;
    });
  }

  document.addEventListener('DOMContentLoaded', mountAll);
  document.addEventListener('turbo:load', mountAll);
  document.addEventListener('turbo:before-cache', unmountAll);
  // Y antes de cualquier render, que NO es lo mismo: con morphing Turbo llega
  // acá sin haber cacheado nada —después de un POST no cachea
  // (`shouldCacheSnapshot = formSubmission.isSafe`), y ese es justo el caso:
  // pedirle algo a la IA y volver a la misma pantalla—. La pantalla se ve
  // bien igual sin esto, medido: el morph reemplaza el contenedor entero y
  // `turbo:load` vuelve a montar. Lo que se perdía era el `unmount()` de la
  // app anterior, que queda viva con sus efectos colgando de nodos sueltos.
  document.addEventListener('turbo:before-render', unmountAll);

  // El script puede haberse ejecutado con el DOM ya listo (Turbo re-ejecuta
  // los <script> del body que reemplaza, y para entonces DOMContentLoaded ya
  // pasó). Sin esto, esa ruta no monta nada.
  if (document.readyState !== 'loading') mountAll();
}
