<template>
  <div class="criteria-editor-island">
    <div v-if="serverErrors.length" class="alert alert-soft alert-error">
      <ul><li v-for="(e, i) in serverErrors" :key="i">{{ e }}</li></ul>
    </div>

    <div v-if="locked || versionsOnSave" class="alert alert-soft alert-warning">{{ lockedReason }}</div>

    <div v-if="versionCreated" class="alert alert-soft alert-success">{{ versionCreated }}</div>

    <div class="panel">
      <div class="field">
        <label>Nombre del set</label>
        <input v-model="form.name" type="text" placeholder="Evaluación técnica" />
      </div>
      <div class="field">
        <label>Descripción</label>
        <input v-model="form.description" type="text" placeholder="Para qué sirve y cuándo usarlo" />
      </div>
    </div>

    <div class="panel">
      <div class="section-head">
        <div>
          <h2 class="section-title">Criterios</h2>
          <p class="muted">Cada uno tiene dos partes: quién le pone el valor, y qué forma tiene ese valor.</p>
        </div>
        <div class="weight-meter" :class="{ 'weight-meter--ok': balanced }">
          <strong>{{ totalWeight }}%</strong>
          <span>{{ balanced ? 'repartido' : 'tiene que sumar 100%' }}</span>
          <button v-if="!balanced && !locked" type="button" class="link-button" @click="distribute">
            Repartir parejo
          </button>
        </div>
      </div>

      <p v-if="!rows.length" class="muted">
        Todavía no hay criterios. Agregá el primero o empezá de una plantilla.
      </p>

      <ol v-else class="criteria-edit-list">
        <criterion-row
          v-for="(criterion, index) in rows"
          :key="criterion.id || criterion.tempId"
          :criterion="criterion"
          :sources="sources"
          :scale-types="scaleTypes"
          :checks="checks"
          :scales="scales"
          :dynamic-options="dynamicOptions"
          :locked="locked"
          @remove="remove(index)"
          @weight="setWeight(index, $event)"
        />
      </ol>

      <div class="criteria-edit-actions">
        <button type="button" class="btn btn-ghost btn-sm" @click="add">+ Agregar criterio</button>
        <template v-if="!rows.length">
          <button type="button" class="btn btn-ghost btn-sm" @click="preset('scoring')">Puntuación clásica</button>
          <button type="button" class="btn btn-ghost btn-sm" @click="preset('gate')">Filtros de admisibilidad</button>
        </template>
      </div>
    </div>

    <div class="editor-actions">
      <span v-if="issues.length" class="field-hint field-hint--warn">{{ issues[0] }}</span>
      <span v-else-if="dirty" class="muted">Sin guardar</span>
      <span v-else-if="saved" class="muted">Guardado</span>
      <span class="editor-actions__spacer"></span>
      <a :href="urls.index" class="btn btn-ghost">Volver</a>
      <button type="button" class="btn btn-primary" :disabled="saving" @click="save">
        {{ saving ? 'Guardando…' : 'Guardar set' }}
      </button>
    </div>
  </div>
</template>

<script>
import CriterionRow from './criterion_row.vue';

// Puntos de partida. No son molde: se editan enteros después.
const PRESETS = {
  scoring: [
    { name: 'Impacto', source: 'manual', scaleType: 'numeric', weight: 40,
      description: 'Cuánto mueve la aguja si funciona.' },
    { name: 'Factibilidad', source: 'manual', scaleType: 'numeric', weight: 35,
      description: 'Qué tan realista es hacerlo con lo que tenemos.' },
    { name: 'Esfuerzo', source: 'manual', scaleType: 'numeric', weight: 25,
      description: 'Cuánto cuesta llevarla adelante.',
      scaleConfig: { min: 1, max: 10, step: 1, direction: 'lower_better' } }
  ],
  gate: [
    { name: 'Está completa', source: 'automatic', weight: 50,
      sourceConfig: { check: 'field_present', min_length: 0 } },
    { name: 'Atendió el feedback', source: 'automatic', weight: 50,
      sourceConfig: { check: 'feedback_addressed' } }
  ]
};

export default {
  name: 'CriteriaEditor',
  components: { CriterionRow },

  props: {
    set: { type: Object, required: true },
    criteria: { type: Array, required: true },
    sources: { type: Array, required: true },
    scaleTypes: { type: Array, required: true },
    checks: { type: Array, required: true },
    scales: { type: Object, required: true },
    formFields: { type: Array, default: () => [] },
    locked: { type: Boolean, default: false },
    lockedReason: { type: String, default: '' },
    versionsOnSave: { type: Boolean, default: false },
    urls: { type: Object, required: true }
  },

  data() {
    return {
      form: { name: this.set.name || '', description: this.set.description || '' },
      rows: this.criteria.map((c) => ({ ...c })),
      saving: false,
      dirty: false,
      saved: false,
      serverErrors: [],
      nextTempId: 1,
      saveUrl: this.urls.save,
      persisted: this.set.persisted,
      versionCreated: ''
    };
  },

  computed: {
    dynamicOptions() { return { form_fields: this.formFields }; },

    activeRows() { return this.rows.filter((c) => c.active); },

    totalWeight() {
      return Math.round(this.activeRows.reduce((sum, c) => sum + Number(c.weight || 0), 0) * 100) / 100;
    },

    balanced() { return Math.abs(this.totalWeight - 100) < 0.01; },

    // Lo que impediría usar el set. Se dice mientras se edita, no al guardar:
    // enterarse de que los pesos no suman recién al apretar guardar es tarde.
    issues() {
      const list = [];
      if (!this.activeRows.length) list.push('El set necesita al menos un criterio activo.');
      else if (!this.balanced) list.push(`Los pesos suman ${this.totalWeight}%, tienen que sumar 100%.`);

      this.activeRows.forEach((c) => {
        if (!c.name) list.push('Hay un criterio sin nombre.');
        if (c.source === 'automatic' && !c.sourceConfig.check) {
          list.push(`«${c.name || 'sin nombre'}»: falta elegir qué verifica.`);
        }
        if (c.source === 'formula' && !c.scaleConfig.expression) {
          list.push(`«${c.name || 'sin nombre'}»: falta la fórmula.`);
        }
      });
      return list;
    }
  },

  watch: {
    rows: { deep: true, handler() { this.dirty = true; this.saved = false; } },
    form: { deep: true, handler() { this.dirty = true; this.saved = false; } }
  },

  methods: {
    blank(attrs = {}) {
      return {
        id: null,
        tempId: `nuevo-${this.nextTempId++}`,
        key: '',
        name: '',
        description: '',
        weight: 0,
        source: 'manual',
        scaleType: 'numeric',
        sourceConfig: {},
        scaleConfig: { min: 1, max: 10, step: 1, direction: 'higher_better' },
        active: true,
        scored: false,
        ...attrs
      };
    },

    add() {
      this.rows.push(this.blank());
      this.distribute();
    },

    remove(index) {
      this.rows.splice(index, 1);
      this.distribute();
    },

    setWeight(index, value) { this.rows[index].weight = value; },

    // Reparte 100% entre los activos, dejando el resto en el primero para que
    // sumen exacto: tres criterios no dan 33.33 tres veces.
    distribute() {
      const active = this.activeRows;
      if (!active.length) return;

      const base = Math.floor((100 / active.length) * 100) / 100;
      active.forEach((c) => { c.weight = base; });
      const remainder = Math.round((100 - base * active.length) * 100) / 100;
      active[0].weight = Math.round((base + remainder) * 100) / 100;
    },

    preset(name) {
      this.rows = PRESETS[name].map((attrs) => this.blank(attrs));
      this.distribute();
    },

    async save() {
      this.saving = true;
      this.serverErrors = [];

      try {
        const response = await fetch(this.saveUrl, {
          method: this.persisted ? 'PUT' : 'POST',
          headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
          },
          body: JSON.stringify({
            name: this.form.name,
            description: this.form.description,
            criteria: this.rows.map((c) => ({
              id: c.id, key: c.key, name: c.name, description: c.description,
              weight: c.weight, source: c.source, scale_type: c.scaleType,
              source_config: c.sourceConfig, scale_config: c.scaleConfig, active: c.active
            }))
          })
        });

        const body = await response.json();

        if (!response.ok) {
          this.serverErrors = body.errors || ['No se pudo guardar el set.'];
          return;
        }

        this.rows = body.criteria.map((c) => ({ ...c }));
        this.persisted = true;
        this.saveUrl = body.urls.save;

        // Se guardó sobre una versión nueva: de acá en adelante se edita esa,
        // y la dirección tiene que acompañar para que recargar no traiga la
        // anterior (que quedó intacta, que es justamente el punto).
        if (body.versioned) {
          this.versionCreated = `Se creó la v${body.set.version}. La anterior sigue en los módulos que ya la usaban.`;
          if (body.urls.edit) window.history.replaceState({}, '', body.urls.show);
        }
        this.$nextTick(() => { this.dirty = false; this.saved = true; });
      } catch (error) {
        this.serverErrors = [`Error de red: ${error.message}`];
      } finally {
        this.saving = false;
      }
    }
  }
};
</script>
