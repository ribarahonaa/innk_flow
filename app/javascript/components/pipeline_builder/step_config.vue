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

    <!-- El formulario de postulación: se resume acá, se edita en su pantalla -->
    <template v-if="step.form">
      <hr class="config-rule" />
      <div class="config-form">
        <label class="config-form__title">Formulario de postulación</label>

        <p v-if="!step.form.count" class="field-hint field-hint--warn">
          Sin campos: nadie puede postular una idea.
        </p>
        <template v-else>
          <p class="config-form__labels">
            {{ step.form.labels.join(' · ') }}<span v-if="step.form.more"> · +{{ step.form.more }}</span>
          </p>
          <p class="field-hint">
            {{ step.form.count }} {{ step.form.count === 1 ? 'campo' : 'campos' }},
            {{ step.form.requiredCount }} {{ step.form.requiredCount === 1 ? 'obligatorio' : 'obligatorios' }}
          </p>
        </template>

        <a :href="step.form.editUrl" class="btn btn-ghost btn-sm">
          {{ step.form.count ? 'Editar el formulario' : 'Definir el formulario' }}
        </a>
      </div>
    </template>

    <!-- Los criterios: se resumen acá, se editan en su pantalla -->
    <template v-if="step.criteria">
      <hr class="config-rule" />
      <div class="config-form">
        <label class="config-form__title">{{ step.kind === 'selection' ? 'Filtros' : 'Criterios' }}</label>

        <select v-if="!step.criteria.own" v-model="step.criteriaSetId" :disabled="step.locked">
          <option :value="null">{{ blankLabel }}</option>
          <option v-for="set in criteriaSets" :key="set.id" :value="set.id">
            {{ set.name }} — {{ set.criteriaCount }} criterios
          </option>
        </select>

        <template v-if="step.criteria.count">
          <p class="config-form__labels">
            {{ step.criteria.labels.join(' · ') }}<span v-if="step.criteria.more"> · +{{ step.criteria.more }}</span>
          </p>
          <p class="field-hint">
            {{ step.criteria.own ? 'Propios de este módulo' : 'De la biblioteca' }} ·
            {{ step.criteria.count }} {{ step.criteria.count === 1 ? 'criterio' : 'criterios' }}
          </p>
          <p v-if="!step.criteria.valid" class="field-hint field-hint--warn">
            Los pesos no suman 100%: el módulo no va a poder arrancar.
          </p>
          <p v-if="step.criteria.newerVersion && !step.locked" class="field-hint field-hint--warn">
            Hay una versión más nueva ({{ step.criteria.newerVersion.label }}). Este módulo sigue con la que tiene.
            <button type="button" class="btn-link" @click="step.criteriaSetId = step.criteria.newerVersion.id">
              Pasarlo a la nueva
            </button>
          </p>
        </template>

        <a :href="step.criteria.editUrl" class="btn btn-ghost btn-sm">
          {{ step.criteria.own ? 'Editar los criterios' : 'Definir criterios propios de este módulo' }}
        </a>
      </div>
    </template>

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
    criteriaSets: { type: Array, default: () => [] },
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

    blankLabel() {
      return this.step.kind === 'selection'
        ? 'Sin filtros'
        : 'Criterios genéricos (impacto, factibilidad, esfuerzo)';
    },

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
