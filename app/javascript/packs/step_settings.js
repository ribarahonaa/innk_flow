// Isla de los ajustes de un módulo. Renderiza los campos que declara
// Flow::StepSettings DENTRO del form de Rails: no guarda por su cuenta.
import StepSettings from '../components/step_settings/step_settings.vue';
import { mountIsland } from '../islands';

mountIsland('step-settings', StepSettings);
