<template>
  <div>
    <h2 class="section-title">{{ step.kindLabel }}</h2>

    <p v-if="step.locked" class="field-hint field-hint--warn config-locked">
      Este módulo ya se ejecutó. Su configuración quedó congelada — cambiarla
      reescribiría lo que ya pasó. El nombre y el modo de IA se siguen ajustando.
    </p>

    <!-- Siempre editables, incluso con el módulo en curso -->
    <div class="field">
      <label>Nombre</label>
      <input v-model="step.name" type="text" />
    </div>

    <div class="field">
      <label>Modo de IA</label>
      <select v-model="step.aiMode">
        <option :value="null">Heredar del desafío ({{ challengeAiLabel }})</option>
        <option v-for="mode in aiModes" :key="mode.value" :value="mode.value">{{ mode.label }}</option>
      </select>
      <p class="field-hint">{{ aiModeDescription }}</p>
    </div>

    <!-- Lo propio del kind, desde el esquema del server -->
    <template v-if="essential.length">
      <hr class="config-rule" />
      <config-field
        v-for="field in essential"
        :key="field.key"
        :field="field"
        :step="step"
        :steps="steps"
        :disabled="step.locked"
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
          :disabled="step.locked"
        />
      </details>
    </template>
  </div>
</template>

<script>
import ConfigField from './config_field.vue';

export default {
  name: 'StepConfig',
  components: { ConfigField },

  props: {
    step: { type: Object, required: true },
    steps: { type: Array, required: true },
    schema: { type: Object, required: true },
    aiModes: { type: Array, required: true },
    challengeAiMode: { type: String, required: true }
  },

  computed: {
    groups() {
      return this.schema[this.step.kind] || { essential: [], advanced: [] };
    },
    essential() { return this.groups.essential || []; },
    advanced() { return this.groups.advanced || []; },

    // Un módulo en curso abre lo avanzado: ahí el panel es para CONSULTAR con
    // qué quedó configurado, y esconder la mitad no ayuda.
    advancedOpen() { return this.step.locked; },

    challengeAiLabel() {
      const mode = this.aiModes.find((m) => m.value === this.challengeAiMode);
      return mode ? mode.label : this.challengeAiMode;
    },
    aiModeDescription() {
      const value = this.step.aiMode || this.challengeAiMode;
      return this.aiModes.find((m) => m.value === value)?.description || '';
    }
  }
};
</script>
