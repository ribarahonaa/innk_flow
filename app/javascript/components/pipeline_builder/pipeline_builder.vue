<template>
  <div class="builder">
    <!-- Paleta -->
    <aside class="builder__palette card">
      <h2 class="section-title">Módulos</h2>
      <p class="muted builder__hint">Hacé clic para agregarlo al final del flujo.</p>

      <button
        v-for="item in palette"
        :key="item.kind"
        type="button"
        class="palette-item"
        :class="{ 'palette-item--disabled': item.disabled || !permissions.canEdit }"
        :disabled="item.disabled || !permissions.canEdit"
        @click="addStep(item)"
      >
        <span class="palette-item__label">
          {{ item.label }}
          <span v-if="item.singleton" class="palette-item__badge">única</span>
        </span>
        <span class="palette-item__desc">{{ item.description }}</span>
        <span v-if="item.disabled" class="palette-item__note">Ya está en el flujo</span>
      </button>
    </aside>

    <!-- Lista ordenada -->
    <section class="builder__flow">
      <div v-if="validation.errors.length" class="flash flash--alert">
        <ul><li v-for="(e, i) in validation.errors" :key="i">{{ e }}</li></ul>
      </div>
      <div v-if="validation.warnings.length" class="flash flash--warn">
        <ul><li v-for="(w, i) in validation.warnings" :key="i">{{ w }}</li></ul>
      </div>
      <div v-if="serverErrors.length" class="flash flash--alert">
        <ul><li v-for="(e, i) in serverErrors" :key="i">{{ e }}</li></ul>
      </div>

      <div v-if="!steps.length" class="card empty-state">
        <p class="muted">El flujo está vacío. Empezá agregando <strong>Idear</strong>.</p>
      </div>

      <ol class="step-list">
        <template v-for="(step, index) in steps" :key="step.id || step.tempId">
          <!-- La línea de agua: todo lo de arriba ya se ejecutó y no se toca -->
          <li v-if="showWaterline(index)" class="waterline">
            <span class="waterline__label">
              ya ejecutado — no se puede insertar arriba de esta línea
            </span>
          </li>

          <li
            class="step-card"
            :class="{
              'step-card--locked': step.locked,
              'step-card--selected': selectedKey === keyOf(step),
              'step-card--dragging': draggingIndex === index
            }"
            :draggable="canDrag(step)"
            @dragstart="onDragStart(index, $event)"
            @dragover.prevent="onDragOver(index)"
            @drop.prevent="onDrop(index)"
            @dragend="onDragEnd"
            @click="select(step)"
          >
            <span class="step-card__handle" :class="{ 'is-hidden': !canDrag(step) }">⠿</span>
            <span class="step-card__index">{{ index + 1 }}</span>

            <span class="step-card__body">
              <span class="step-card__name">{{ step.name }}</span>
              <span class="step-card__meta">
                <span class="step-card__kind">{{ step.kindLabel }}</span>
                <span class="step-card__ai">{{ aiLabel(step) }}</span>
              </span>
            </span>

            <span class="status-chip" :class="`status-chip--${step.status}`">
              {{ step.statusLabel }}
            </span>
            <span v-if="step.locked" class="step-card__lock" title="Módulo ya ejecutado">🔒</span>

            <button
              v-if="!step.locked && permissions.canEdit"
              type="button"
              class="step-card__remove"
              title="Quitar del flujo"
              @click.stop="removeStep(index)"
            >×</button>
          </li>
        </template>
      </ol>
    </section>

    <!-- Configuración del módulo seleccionado -->
    <aside class="builder__config card">
      <template v-if="selected">
        <h2 class="section-title">{{ selected.kindLabel }}</h2>

        <!--
          Nombre y modo de IA se pueden cambiar aunque el módulo ya esté en
          curso: renombrar no altera nada, y el modo es una política operativa
          ("a partir de ahora acepto ayuda de la IA"), no parte del historial.
          Lo estructural —tipo, posición, configuración— sí queda congelado.
        -->
        <div class="field">
          <label>Nombre</label>
          <input v-model="selected.name" type="text" />
        </div>

        <div class="field">
          <label>Modo de IA</label>
          <select v-model="selected.aiMode">
            <option :value="null">Heredar del desafío ({{ challengeAiLabel }})</option>
            <option v-for="mode in aiModes" :key="mode.value" :value="mode.value">
              {{ mode.label }}
            </option>
          </select>
          <p class="field-hint">{{ aiModeDescription }}</p>
        </div>

        <!-- Selección: de qué evaluación toma el puntaje -->
        <div v-if="selected.kind === 'selection'" class="field">
          <label>Puntaje que usa para ordenar</label>
          <select v-model="selected.sourceStepId" :disabled="selected.locked">
            <option :value="null">Automático (la evaluación previa más cercana)</option>
            <option v-for="s in evaluationsBefore(selected)" :key="s.id" :value="s.id">
              {{ s.name }}
            </option>
          </select>
          <p v-if="!evaluationsBefore(selected).length" class="field-hint field-hint--warn">
            No hay ninguna evaluación antes de este módulo.
          </p>
        </div>

        <div v-if="selected.kind === 'selection'" class="field">
          <label>Regla de corte</label>
          <select v-model="selected.settings.cut_mode" :disabled="selected.locked">
            <option value="manual">Manual (el dueño decide)</option>
            <option value="top_n">Top N ideas</option>
            <option value="top_percent">Top N %</option>
            <option value="threshold">Puntaje mínimo</option>
          </select>
        </div>
        <div v-if="selected.kind === 'selection' && selected.settings.cut_mode && selected.settings.cut_mode !== 'manual'" class="field">
          <label>Valor</label>
          <input v-model.number="selected.settings.cut_value" type="number" min="1" :disabled="selected.locked" />
        </div>

        <!-- Criterios del módulo de evaluación -->
        <div v-if="selected.kind === 'evaluation'" class="field">
          <label>Set de criterios</label>
          <select v-model="selected.criteriaSetId" :disabled="selected.locked">
            <option :value="null">Criterios por defecto (impacto, factibilidad, esfuerzo)</option>
            <option v-for="set in criteriaSets" :key="set.id" :value="set.id">
              {{ set.name }} — {{ set.criteriaCount }} criterios
            </option>
          </select>
          <p v-if="selectedCriteriaSet" class="field-hint">
            {{ selectedCriteriaSet.summary }}
            <a :href="selectedCriteriaSet.editUrl" class="field-hint__link">editar</a>
          </p>
          <p v-else class="field-hint">
            Se crean tres criterios genéricos al activar el módulo, editables desde ahí.
            <a :href="urls.newCriteriaSet" class="field-hint__link">Crear un set propio</a>
          </p>
          <p v-if="selectedCriteriaSet && selectedCriteriaSet.status !== 'valid'" class="field-hint field-hint--warn">
            Este set tiene algo que revisar: los pesos de sus criterios deben sumar 100%.
          </p>
        </div>

        <div v-if="selected.kind === 'evaluation'" class="field">
          <label>Evaluaciones mínimas por idea</label>
          <input v-model.number="selected.settings.min_assessments" type="number" min="1" :disabled="selected.locked" />
        </div>

        <div v-if="selected.kind === 'ideation'" class="field">
          <label>Ideas mínimas para poder avanzar</label>
          <input v-model.number="selected.settings.min_ideas" type="number" min="1" :disabled="selected.locked" />
        </div>

        <p v-if="selected.locked" class="field-hint field-hint--warn">
          Este módulo ya se ejecutó: su tipo, posición y configuración quedaron
          congelados. El nombre y el modo de IA se pueden seguir ajustando.
        </p>
      </template>
      <template v-else>
        <h2 class="section-title">Configuración</h2>
        <p class="muted">Elegí un módulo del flujo para configurarlo.</p>
      </template>
    </aside>

    <!-- Barra de acciones -->
    <footer class="builder__actions">
      <span v-if="dirty" class="muted">Hay cambios sin guardar.</span>
      <span v-else-if="savedAt" class="muted">Guardado.</span>
      <span class="builder__spacer"></span>
      <button type="button" class="btn btn--ghost" :disabled="saving" @click="save">
        {{ saving ? 'Guardando…' : 'Guardar flujo' }}
      </button>
      <a v-if="permissions.canStart && !dirty && validation.valid" class="btn btn--primary" :href="urls.show">
        Ir al desafío
      </a>
    </footer>
  </div>
</template>

<script>
export default {
  name: 'PipelineBuilder',

  props: {
    challenge: { type: Object, required: true },
    steps: { type: Array, required: true },
    palette: { type: Array, required: true },
    aiModes: { type: Array, required: true },
    criteriaSets: { type: Array, default: () => [] },
    insertionFloor: { type: Number, default: null },
    validation: { type: Object, required: true },
    permissions: { type: Object, required: true },
    urls: { type: Object, required: true }
  },

  data() {
    return {
      selectedKey: null,
      draggingIndex: null,
      dropIndex: null,
      saving: false,
      dirty: false,
      savedAt: null,
      serverErrors: [],
      nextTempId: 1
    };
  },

  computed: {
    selected() {
      return this.steps.find((s) => this.keyOf(s) === this.selectedKey) || null;
    },

    selectedCriteriaSet() {
      if (!this.selected || !this.selected.criteriaSetId) return null;
      return this.criteriaSets.find((set) => set.id === this.selected.criteriaSetId) || null;
    },

    challengeAiLabel() {
      const mode = this.aiModes.find((m) => m.value === this.challenge.aiDefaultMode);
      return mode ? mode.label : this.challenge.aiDefaultMode;
    },

    aiModeDescription() {
      const value = this.selected?.aiMode || this.challenge.aiDefaultMode;
      return this.aiModes.find((m) => m.value === value)?.description || '';
    },

    // Índice del primer módulo NO tocado: ahí va la línea de agua.
    firstUnlockedIndex() {
      const index = this.steps.findIndex((s) => !s.locked);
      return index === -1 ? this.steps.length : index;
    }
  },

  watch: {
    steps: {
      deep: true,
      handler() { this.dirty = true; }
    }
  },

  methods: {
    keyOf(step) { return step.id || step.tempId; },

    aiLabel(step) {
      const value = step.aiMode || this.challenge.aiDefaultMode;
      const mode = this.aiModes.find((m) => m.value === value);
      const label = mode ? mode.label : value;
      return step.aiMode ? label : `${label} (heredado)`;
    },

    select(step) { this.selectedKey = this.keyOf(step); },

    // La línea de agua solo se dibuja si hay algo tocado y algo por delante.
    showWaterline(index) {
      return index === this.firstUnlockedIndex && index > 0;
    },

    canDrag(step) {
      return this.permissions.canEdit && this.permissions.canReorder && !step.locked;
    },

    evaluationsBefore(step) {
      const index = this.steps.indexOf(step);
      return this.steps.slice(0, index).filter((s) => s.kind === 'evaluation');
    },

    addStep(item) {
      if (item.disabled || !this.permissions.canEdit) return;

      const step = {
        id: null,
        tempId: `new-${this.nextTempId++}`,
        kind: item.kind,
        kindLabel: item.label,
        name: item.label,
        status: 'pending',
        statusLabel: 'Pendiente',
        aiMode: null,
        sourceStepId: null,
        criteriaSetId: null,
        settings: {},
        locked: false,
        removable: true
      };

      this.steps.push(step);
      this.selectedKey = this.keyOf(step);
      this.refreshPalette();
    },

    removeStep(index) {
      const [removed] = this.steps.splice(index, 1);
      if (this.selectedKey === this.keyOf(removed)) this.selectedKey = null;
      this.refreshPalette();
    },

    // Los módulos "únicos" (Idear) se deshabilitan cuando ya están en el flujo.
    refreshPalette() {
      const kinds = this.steps.map((s) => s.kind);
      this.palette.forEach((item) => {
        if (item.singleton) item.disabled = kinds.includes(item.kind);
      });
    },

    onDragStart(index, event) {
      if (!this.canDrag(this.steps[index])) {
        event.preventDefault();
        return;
      }
      this.draggingIndex = index;
      event.dataTransfer.effectAllowed = 'move';
    },

    onDragOver(index) { this.dropIndex = index; },

    onDrop(targetIndex) {
      const from = this.draggingIndex;
      if (from === null || from === targetIndex) return;

      // No se puede soltar por encima de la línea de agua: el prefijo ya
      // ejecutado es inmovible. El server lo revalida igual.
      if (targetIndex < this.firstUnlockedIndex) return;

      const [moved] = this.steps.splice(from, 1);
      this.steps.splice(targetIndex, 0, moved);
      this.draggingIndex = null;
    },

    onDragEnd() {
      this.draggingIndex = null;
      this.dropIndex = null;
    },

    async save() {
      this.saving = true;
      this.serverErrors = [];

      const payload = {
        lock_version: this.challenge.lockVersion,
        steps: this.steps.map((s) => ({
          id: s.id,
          kind: s.kind,
          name: s.name,
          aiMode: s.aiMode,
          sourceStepId: s.sourceStepId,
          criteriaSetId: s.criteriaSetId,
          settings: s.settings || {}
        }))
      };

      try {
        const response = await fetch(this.urls.pipeline, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
          },
          body: JSON.stringify(payload)
        });

        const body = await response.json();

        if (!response.ok) {
          this.serverErrors = body.errors || ['No se pudo guardar el flujo.'];
          return;
        }

        // El server es la fuente de verdad: se reemplaza el estado entero con
        // lo que devolvió, incluidas posiciones renumeradas e ids reales.
        this.applyServerState(body);
      } catch (error) {
        this.serverErrors = [`Error de red: ${error.message}`];
      } finally {
        this.saving = false;
      }
    },

    applyServerState(body) {
      this.steps.splice(0, this.steps.length, ...body.steps);
      this.palette.splice(0, this.palette.length, ...body.palette);
      Object.assign(this.challenge, body.challenge);
      Object.assign(this.validation, body.validation);
      Object.assign(this.permissions, body.permissions);

      this.$nextTick(() => {
        this.dirty = false;
        this.savedAt = new Date();
      });
    }
  }
};
</script>
