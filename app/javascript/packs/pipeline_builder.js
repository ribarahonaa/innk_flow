// Isla del builder de pipeline.
//
// Monta sobre [data-island="pipeline-builder"] con las props que serializó
// PipelinePresenter en el server. No hay fetch al montar: el primer render ya
// tiene todo, y el server es dueño de la tenencia del payload.
import { createApp } from 'vue';
import PipelineBuilder from '../components/pipeline_builder/pipeline_builder.vue';

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-island="pipeline-builder"]').forEach((el) => {
    const props = JSON.parse(el.dataset.props);
    el.innerHTML = '';
    createApp(PipelineBuilder, props).mount(el);
  });
});
