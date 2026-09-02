<template>
  <div class="levels">
    <div class="levels__row levels__row--head">
      <span v-for="column in columns" :key="column">{{ heading(column) }}</span>
      <span></span>
    </div>

    <div v-for="(level, index) in value" :key="index" class="levels__row">
      <input
        v-for="column in columns"
        :key="column"
        :type="column === 'value' ? 'number' : 'text'"
        :value="level[column]"
        :disabled="disabled"
        @input="set(level, column, $event.target.value)"
      />
      <button type="button" class="levels__remove" :disabled="disabled" @click="value.splice(index, 1)">×</button>
    </div>

    <button type="button" class="btn btn--ghost btn--sm" :disabled="disabled" @click="add">+ Agregar nivel</button>
  </div>
</template>

<script>
const HEADINGS = { key: 'Clave', label: 'Se ve como', value: 'Vale', descriptor: 'Qué significa' };

export default {
  name: 'LevelsField',

  props: {
    value: { type: Array, required: true },
    columns: { type: Array, required: true },
    disabled: { type: Boolean, default: false }
  },

  methods: {
    heading(column) { return HEADINGS[column] || column; },

    set(level, column, raw) {
      level[column] = column === 'value' ? Number(raw) : raw;
    },

    add() {
      const level = {};
      this.columns.forEach((column) => { level[column] = column === 'value' ? 0 : ''; });
      this.value.push(level);
    }
  }
};
</script>
