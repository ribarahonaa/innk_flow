// Isla del builder de pipeline.
//
// Las props las serializa PipelinePresenter en el server y viajan en
// data-props: no hay fetch al montar, y la tenencia la garantiza el scope de
// Ruby en vez de una ruta JSON que alguien podría olvidar scopear.
import PipelineBuilder from '../components/pipeline_builder/pipeline_builder.vue';
import { mountIsland } from '../islands';

mountIsland('pipeline-builder', PipelineBuilder);
