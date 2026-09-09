<template>
  <div>
    <!-- Lo propio del kind, desde el esquema del server -->
    <template v-if="essential.length">
      <config-field
        v-for="field in essential"
        :key="field.key"
        :field="field"
        :step="step"
        :steps="steps"
        :fields="todos"
      />
    </template>

    <template v-if="advanced.length">
      <details class="config-advanced" :open="advancedOpen">
        <summary>Opciones avanzadas</summary>
        <config-field
          v-for="field in advanced"
          :key="field.key"
          :field="field"
          :step="step"
          :steps="steps"
          :fields="todos"
        />
      </details>
    </template>
  </div>
</template>

<script>
import ConfigField from './config_field.vue';

export default {
  name: 'StepSettings',
  components: { ConfigField },

  props: {
    kind: { type: String, required: true },
    stepId: { type: String, required: true },
    settings: { type: Object, default: () => ({}) },
    sourceStepId: { type: String, default: null },
    steps: { type: Array, default: () => [] },
    schema: { type: Object, required: true }
  },

  // Las props son el estado INICIAL, no el estado: Vue no las hace reactivas
  // en la raíz. Se copia a data() una vez y se trabaja sobre la copia.
  data() {
    return {
      step: {
        id: this.stepId,
        kind: this.kind,
        settings: JSON.parse(JSON.stringify(this.settings)),
        sourceStepId: this.sourceStepId,
        locked: false
      }
    };
  },

  computed: {
    groups() {
      return this.schema[this.step.kind] || { essential: [], advanced: [] };
    },
    essential() { return this.groups.essential || []; },
    advanced() { return this.groups.advanced || []; },
    todos() { return this.essential.concat(this.advanced); },

    // El módulo pendiente es el único caso en que este panel existe, así que
    // «avanzado» no tiene nada que ocultar por defecto.
    advancedOpen() { return this.step.locked; }
  }
};
</script>
