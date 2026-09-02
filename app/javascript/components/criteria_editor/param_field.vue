<template>
  <div class="param" :class="{ 'param--wide': param.type === 'levels' }">
    <label>{{ param.label }}</label>

    <levels-field v-if="param.type === 'levels'" :value="levels" :columns="param.columns" :disabled="disabled" />

    <div v-else class="param__control">
      <select v-if="param.type === 'select'" :value="value" :disabled="disabled" @change="write($event.target.value)">
        <option v-if="param.blank" :value="''">{{ param.blank }}</option>
        <option v-for="option in options" :key="option.value" :value="option.value">{{ option.label }}</option>
      </select>

      <input
        v-else-if="param.type === 'number'"
        type="number"
        :value="value"
        :min="param.min"
        :max="param.max"
        :disabled="disabled"
        @input="write($event.target.value === '' ? null : Number($event.target.value))"
      />

      <input
        v-else
        type="text"
        :value="value"
        :placeholder="param.placeholder"
        :class="{ 'code-input': param.mono }"
        :disabled="disabled"
        @input="write($event.target.value)"
      />

      <span v-if="param.suffix" class="param__suffix">{{ param.suffix }}</span>
    </div>

    <p v-if="param.hint" class="field-hint">{{ param.hint }}</p>
  </div>
</template>

<script>
import LevelsField from './levels_field.vue';
import { readNested, writeNested } from './nested';

export default {
  name: 'ParamField',
  components: { LevelsField },

  props: {
    param: { type: Object, required: true },
    config: { type: Object, required: true },
    // Opciones que dependen del desafío, resueltas por el server.
    dynamicOptions: { type: Object, default: () => ({}) },
    disabled: { type: Boolean, default: false }
  },

  computed: {
    value() {
      const raw = readNested(this.config, this.param.key);
      return raw === undefined || raw === null ? this.param.default ?? '' : raw;
    },

    levels() {
      let list = readNested(this.config, this.param.key);
      if (!Array.isArray(list)) {
        list = JSON.parse(JSON.stringify(this.param.default || []));
        writeNested(this.config, this.param.key, list);
      }
      return list;
    },

    options() {
      if (this.param.source) return this.dynamicOptions[this.param.source] || [];
      return this.param.options || [];
    }
  },

  methods: {
    write(value) { writeNested(this.config, this.param.key, value); }
  }
};
</script>
