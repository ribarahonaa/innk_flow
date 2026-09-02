<template>
  <div class="form-editor">
    <div v-if="serverErrors.length" class="flash flash--alert">
      <ul><li v-for="(e, i) in serverErrors" :key="i">{{ e }}</li></ul>
    </div>

    <p v-if="!rows.length && !startedEmpty" class="field-hint field-hint--warn">
      Te quedaste sin campos. Si guardás así, nadie va a poder postular.
    </p>

    <ol v-else class="field-editor">
      <li
        v-for="(field, index) in rows"
        :key="field.id || field.tempId"
        class="field-edit"
        :class="{ 'field-edit--dragging': draggingIndex === index, 'field-edit--over': overIndex === index }"
        draggable="true"
        @dragstart="onDragStart(index, $event)"
        @dragover.prevent="overIndex = index"
        @dragleave="overIndex === index && (overIndex = null)"
        @drop.prevent="onDrop(index)"
        @dragend="reset"
      >
        <span class="field-edit__handle" title="Arrastrar para reordenar">⠿</span>

        <div class="field-edit__body">
          <div class="field-edit__line">
            <input
              v-model="field.label"
              class="field-edit__label"
              type="text"
              placeholder="Qué se le pregunta a quien postula"
            />
            <select v-model="field.fieldType" :disabled="locked && !!field.id">
              <option v-for="t in fieldTypes" :key="t.value" :value="t.value">{{ t.label }}</option>
            </select>
          </div>

          <input
            v-model="field.hint"
            class="field-edit__hint"
            type="text"
            placeholder="Texto de ayuda (opcional)"
          />

          <input
            v-if="needsOptions(field)"
            class="field-edit__hint"
            type="text"
            placeholder="Opciones separadas por coma"
            :value="field.options.join(', ')"
            @input="setOptions(field, $event.target.value)"
          />

          <div class="field-edit__flags">
            <label><input v-model="field.required" type="checkbox" /> Obligatorio</label>
            <label>
              <input type="radio" :checked="field.isTitle" @change="setTitle(field)" />
              Es el título de la idea
            </label>
            <code class="field-edit__key">{{ field.key || 'clave: se genera del nombre' }}</code>
            <span v-if="field.answered" class="field-edit__answered">
              {{ field.answered }} {{ field.answered === 1 ? 'idea respondió' : 'ideas respondieron' }}
            </span>
          </div>
        </div>

        <button
          v-if="!locked || !field.id"
          type="button"
          class="field-edit__remove"
          title="Quitar campo"
          @click="remove(index)"
        >×</button>
      </li>
    </ol>

    <div class="field-editor__actions">
      <button type="button" class="btn btn--ghost btn--sm" @click="add">+ Agregar campo</button>
      <span class="editor-actions__spacer"></span>
      <span v-if="dirty" class="muted">Sin guardar</span>
      <span v-else-if="saved" class="muted">Guardado</span>
      <a :href="urls.back" class="btn btn--ghost">Volver al flujo</a>
      <button type="button" class="btn btn--primary" :disabled="saving || nothingToSave" @click="save">
        {{ saving ? 'Guardando…' : 'Guardar formulario' }}
      </button>
    </div>
  </div>
</template>

<script>
export default {
  name: 'FormEditor',

  props: {
    fields: { type: Array, required: true },
    fieldTypes: { type: Array, required: true },
    locked: { type: Boolean, default: false },
    urls: { type: Object, required: true }
  },

  data() {
    return {
      rows: this.fields.map((f) => ({ ...f, options: f.options || [] })),
      // El módulo que nace vacío ya se explica en la tarjeta de arriba; el
      // aviso de Vue es para el caso distinto: quedarse sin campos borrando.
      startedEmpty: this.fields.length === 0,
      draggingIndex: null,
      overIndex: null,
      saving: false,
      dirty: false,
      saved: false,
      serverErrors: [],
      nextTempId: 1
    };
  },

  watch: {
    rows: { deep: true, handler() { this.dirty = true; this.saved = false; } }
  },

  computed: {
    nothingToSave() { return this.startedEmpty && this.rows.length === 0; }
  },

  methods: {
    needsOptions(field) { return ['select', 'multi_select'].includes(field.fieldType); },

    setOptions(field, raw) {
      field.options = raw.split(',').map((o) => o.trim()).filter(Boolean);
    },

    // El título de la idea es uno solo: marcar uno desmarca al resto.
    setTitle(field) {
      this.rows.forEach((f) => { f.isTitle = f === field; });
    },

    add() {
      this.rows.push({
        id: null,
        tempId: `nuevo-${this.nextTempId++}`,
        key: '',
        label: '',
        hint: '',
        fieldType: 'text',
        required: false,
        isTitle: this.rows.every((f) => !f.isTitle),
        options: [],
        answered: 0
      });
    },

    remove(index) { this.rows.splice(index, 1); },

    onDragStart(index, event) {
      this.draggingIndex = index;
      event.dataTransfer.effectAllowed = 'move';
    },

    onDrop(target) {
      const from = this.draggingIndex;
      this.reset();
      if (from === null || from === target) return;
      const [moved] = this.rows.splice(from, 1);
      this.rows.splice(target, 0, moved);
    },

    reset() { this.draggingIndex = null; this.overIndex = null; },

    async save() {
      this.saving = true;
      this.serverErrors = [];

      try {
        const response = await fetch(this.urls.save, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
          },
          body: JSON.stringify({
            fields: this.rows.map((f) => ({
              id: f.id,
              key: f.key,
              label: f.label,
              hint: f.hint,
              field_type: f.fieldType,
              required: f.required,
              is_title: f.isTitle,
              options: f.options
            }))
          })
        });

        const body = await response.json();

        if (!response.ok) {
          this.serverErrors = body.errors || ['No se pudo guardar el formulario.'];
          return;
        }

        // El server devuelve la lista canónica: ids nuevos, claves derivadas,
        // posiciones renumeradas. Se reemplaza en vez de confiar en lo local.
        this.rows = body.fields.map((f) => ({ ...f, options: f.options || [] }));
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
