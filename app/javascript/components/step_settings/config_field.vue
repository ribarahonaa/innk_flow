<template>
  <div v-if="visible" class="field">
    <label :for="inputId">{{ field.label }}</label>

    <select v-if="field.type === 'select'" :id="inputId" v-model="value" :name="inputName" :disabled="disabled">
      <option v-if="field.blank" :value="null">{{ field.blank }}</option>
      <option v-for="opt in options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>

    <select
      v-else-if="field.type === 'multi_select'"
      :id="inputId"
      v-model="value"
      :name="inputName"
      multiple
      :disabled="disabled"
    >
      <option v-for="opt in options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>

    <label v-else-if="field.type === 'boolean'" class="field-check">
      <!-- Rails necesita el hidden ANTES: un checkbox desmarcado no manda
           nada, y `config` se guarda por reemplazo total — sin esto la
           clave desaparece en vez de guardarse en `false`. -->
      <input type="hidden" :name="inputName" value="0" />
      <input :id="inputId" v-model="value" type="checkbox" :name="inputName" :disabled="disabled" />
      <span>{{ field.checkboxLabel || 'Activado' }}</span>
    </label>

    <input
      v-else
      :id="inputId"
      v-model.number="value"
      type="number"
      :name="inputName"
      :min="field.min"
      :max="field.max"
      :disabled="disabled"
    />

    <p v-if="field.hint" class="field-hint">{{ field.hint }}</p>
    <p v-if="emptyOptions" class="field-hint field-hint--warn">
      No hay opciones disponibles todavía.
    </p>
  </div>
</template>

<script>
export default {
  name: 'ConfigField',

  props: {
    field: { type: Object, required: true },
    step: { type: Object, required: true },
    steps: { type: Array, required: true },
    // Los demás campos del mismo esquema: `depends_on` necesita el DEFAULT del
    // campo al que apunta, no sólo su valor guardado.
    fields: { type: Array, default: () => [] },
    disabled: { type: Boolean, default: false }
  },

  computed: {
    inputId() { return `cfg-${this.step.id || this.step.tempId}-${this.field.key.replace('.', '-')}`; },

    // Un campo puede depender de otro: el valor del corte no tiene sentido con
    // la regla en «manual».
    visible() {
      const rule = this.field.depends_on;
      if (!rule) return true;

      // Contra el valor EFECTIVO. Un módulo recién creado no tiene `cut` en
      // settings, así que leer a secas daba `undefined` —que no es "manual"—
      // y «Valor del corte» aparecía debajo de una regla que dice Manual.
      let other = this.read(rule.key);
      if (other === undefined || other === null) {
        other = this.fields.find((f) => f.key === rule.key)?.default;
      }

      if (rule.not !== undefined) return other !== rule.not;
      if (rule.is !== undefined) return other === rule.is;
      return true;
    },

    // Las opciones que apuntan a otros módulos se filtran contra la posición
    // del módulo actual: una selección solo puede tomar el puntaje de una
    // evaluación ANTERIOR, y el orden cambia mientras se edita el flujo.
    //
    // Por `id`, no por referencia: en el builder viejo `step` salía de un
    // `find()` sobre el mismo array `steps`, así que `indexOf` funcionaba. En
    // esta isla `step` es un objeto NUEVO armado en `data()` —nunca es el
    // mismo objeto que viaja en `steps`—, así que `indexOf` daba siempre -1 y
    // no filtraba nada. Sin `id` (no debería pasar: esta isla siempre monta
    // sobre un módulo ya guardado) no hay de dónde tomar la posición, y no
    // filtrar es peor que no ofrecer nada.
    options() {
      const opts = this.field.options || [];
      if (!opts.length || opts[0].position === undefined) return opts;

      const mine = this.step.id && this.steps.find((s) => s.id === this.step.id);
      const before = mine ? this.steps.filter((s) => s.position < mine.position) : [];
      const allowed = new Set(before.map((s) => s.id).concat(before.map((s) => s.slug)));
      return opts.filter((o) => allowed.has(o.value));
    },

    emptyOptions() {
      return ['select', 'multi_select'].includes(this.field.type) &&
             !this.options.length && !this.field.blank;
    },

    // El input viaja DENTRO del form de Rails: la isla no guarda, renderiza.
    // Un solo botón «Guardar el módulo» manda nombre, modo de IA y ajustes
    // juntos contra un solo endpoint.
    //
    // `multi_select` necesita el sufijo `[]`: sin él, un `<select multiple>`
    // manda varios pares con la MISMA clave (`clave=a&clave=b`) y Rack se
    // queda solo con el último — elegir tres módulos en «Qué módulos abarca»
    // guardaba uno.
    inputName() {
      if (this.field.column === true) {
        return `challenge_step[${this.field.key}]`;
      }
      const rutas = this.field.key.split('.').map((s) => `[${s}]`).join('');
      const sufijo = this.field.type === 'multi_select' ? '[]' : '';
      return `challenge_step[config]${rutas}${sufijo}`;
    },

    value: {
      get() {
        const current = this.read(this.field.key);
        if (current !== undefined && current !== null) return current;
        if (this.field.type === 'multi_select') return [];
        return this.field.default !== undefined ? this.field.default : null;
      },
      set(val) { this.write(this.field.key, val); }
    }
  },

  methods: {
    // `column: true` vive en el step (criteriaSetId, sourceStepId); el resto
    // en settings, con claves que pueden ser anidadas ("cut.mode").
    read(key) {
      if (this.isColumn(key)) return this.step[this.columnName(key)];

      return key.split('.').reduce((node, seg) => (node == null ? undefined : node[seg]),
                                   this.step.settings || {});
    },

    write(key, val) {
      if (this.isColumn(key)) {
        this.step[this.columnName(key)] = val;
        return;
      }

      if (!this.step.settings) this.step.settings = {};
      const segs = key.split('.');
      const last = segs.pop();
      let node = this.step.settings;
      segs.forEach((seg) => {
        if (typeof node[seg] !== 'object' || node[seg] === null) node[seg] = {};
        node = node[seg];
      });
      node[last] = val;
    },

    isColumn(key) {
      const field = key === this.field.key ? this.field : null;
      if (field) return field.column === true;
      return ['criteria_set_id', 'source_step_id'].includes(key);
    },

    columnName(key) {
      return { criteria_set_id: 'criteriaSetId', source_step_id: 'sourceStepId' }[key] || key;
    }
  }
};
</script>
