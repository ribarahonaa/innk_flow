<template>
  <li class="criterion-edit" :class="{ 'criterion-edit--off': !criterion.active }">
    <div class="criterion-edit__head">
      <input v-model="criterion.name" type="text" class="criterion-edit__name" placeholder="Nombre del criterio" />

      <div class="criterion-edit__weight">
        <input
          type="number"
          min="0"
          max="100"
          step="1"
          :value="criterion.weight"
          :disabled="locked || !criterion.active"
          @input="$emit('weight', Number($event.target.value))"
        />
        <span>%</span>
      </div>

      <button type="button" class="criterion-edit__remove" :disabled="locked && criterion.id" @click="$emit('remove')">×</button>
    </div>

    <p class="criterion-edit__summary">{{ summary }}</p>

    <div class="criterion-edit__grid">
      <div class="param">
        <label>Quién le pone el valor</label>
        <select v-model="criterion.source" :disabled="locked && criterion.id" @change="onSourceChange">
          <option v-for="source in sources" :key="source.value" :value="source.value">{{ source.label }}</option>
        </select>
      </div>

      <!-- Automático: qué verifica el sistema -->
      <div v-if="criterion.source === 'automatic'" class="param">
        <label>Qué verifica</label>
        <select :value="checkType" :disabled="locked && criterion.id" @change="onCheckChange($event.target.value)">
          <option value="">Elegí una verificación</option>
          <option v-for="check in checks" :key="check.value" :value="check.value">{{ check.label }}</option>
        </select>
        <p v-if="activeCheck" class="field-hint">{{ activeCheck.summary }}</p>
      </div>

      <!-- Manual o IA: qué forma tiene el valor -->
      <div v-else-if="choosesScale" class="param">
        <label>Forma del valor</label>
        <select v-model="criterion.scaleType" :disabled="locked && criterion.id" @change="onScaleChange">
          <option v-for="scale in scaleTypes" :key="scale.value" :value="scale.value">{{ scale.label }}</option>
        </select>
        <p v-if="activeScale" class="field-hint">{{ activeScale.summary }}</p>
      </div>

      <param-field
        v-for="param in checkParams"
        :key="`check-${param.key}`"
        :param="param"
        :config="criterion.sourceConfig"
        :dynamic-options="dynamicOptions"
        :disabled="locked && !!criterion.id"
      />

      <param-field
        v-for="param in scaleParams"
        :key="`scale-${param.key}`"
        :param="param"
        :config="criterion.scaleConfig"
        :dynamic-options="dynamicOptions"
        :disabled="locked && !!criterion.id"
      />
    </div>

    <div class="criterion-edit__foot">
      <input v-model="criterion.description" type="text" class="criterion-edit__desc"
             placeholder="Qué mirar al puntuarlo (lo lee quien evalúa)" />
      <label class="criterion-edit__flag">
        <input v-model="criterion.active" type="checkbox" :disabled="locked && criterion.id" />
        Activo
      </label>
      <code class="criterion-edit__key" :title="'Las fórmulas lo usan como variable'">{{ criterion.key || 'clave: del nombre' }}</code>
      <span v-if="criterion.scored" class="criterion-edit__scored">ya tiene notas</span>
    </div>
  </li>
</template>

<script>
import ParamField from './param_field.vue';
import { readNested, writeNested } from './nested';

export default {
  name: 'CriterionRow',
  components: { ParamField },

  props: {
    criterion: { type: Object, required: true },
    sources: { type: Array, required: true },
    scaleTypes: { type: Array, required: true },
    checks: { type: Array, required: true },
    scales: { type: Object, required: true },
    dynamicOptions: { type: Object, default: () => ({}) },
    locked: { type: Boolean, default: false }
  },

  emits: ['remove', 'weight'],

  computed: {
    choosesScale() {
      return this.sources.find((s) => s.value === this.criterion.source)?.choosesScale;
    },

    checkType() { return this.criterion.sourceConfig.check || ''; },
    activeCheck() { return this.checks.find((c) => c.value === this.checkType); },
    checkParams() {
      return this.criterion.source === 'automatic' ? (this.activeCheck?.params || []) : [];
    },

    activeScale() { return this.scaleTypes.find((s) => s.value === this.criterion.scaleType); },

    // El automático no configura escala: es sí/no por definición y nadie lo
    // elige en un formulario. Misma regla que en Flow::CriterionSettings.
    scaleKey() {
      if (this.criterion.source === 'formula') return 'formula';
      return this.criterion.scaleType;
    },
    scaleParams() {
      if (this.criterion.source === 'automatic') return [];
      return this.scales[this.scaleKey] || [];
    },

    summary() {
      if (this.criterion.source === 'automatic') {
        return this.activeCheck ? `El sistema lo verifica: ${this.activeCheck.summary.toLowerCase()}` : 'El sistema lo verifica.';
      }
      if (this.criterion.source === 'formula') {
        const expression = readNested(this.criterion.scaleConfig, 'expression');
        return expression ? `Se calcula: ${expression}` : 'Se calcula a partir de los otros criterios.';
      }
      const who = this.sources.find((s) => s.value === this.criterion.source)?.label;
      return `${who} · ${this.activeScale?.label || ''}`;
    }
  },

  methods: {
    // Cambiar de origen no arrastra la config del anterior: se siembra la del
    // nuevo con sus valores por defecto.
    onSourceChange() {
      this.criterion.sourceConfig = {};
      this.criterion.scaleConfig = {};
      if (this.criterion.source === 'automatic') this.criterion.scaleType = 'boolean';
      if (this.criterion.source === 'formula') this.criterion.scaleType = 'numeric';
      if (this.choosesScale && !this.scaleTypes.find((s) => s.value === this.criterion.scaleType)) {
        this.criterion.scaleType = this.scaleTypes[0]?.value;
      }
      this.seedDefaults(this.criterion.scaleConfig, this.scaleParams);
    },

    onCheckChange(type) {
      this.criterion.sourceConfig = { check: type };
      this.seedDefaults(this.criterion.sourceConfig, this.checks.find((c) => c.value === type)?.params || []);
    },

    onScaleChange() {
      this.criterion.scaleConfig = {};
      this.seedDefaults(this.criterion.scaleConfig, this.scaleParams);
    },

    seedDefaults(config, params) {
      params.forEach((param) => {
        if (param.default === undefined) return;
        writeNested(config, param.key, JSON.parse(JSON.stringify(param.default)));
      });
    }
  }
};
</script>
