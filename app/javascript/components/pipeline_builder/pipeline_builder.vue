<template>
  <div class="builder" :class="{ 'builder--dirty': dirty }">
    <!-- Paleta -->
    <aside class="builder__palette card">
      <h2 class="section-title">Módulos</h2>
      <p class="muted builder__hint">Hacé clic para agregarlo al final del flujo.</p>

      <button
        v-for="item in localPalette"
        :key="item.kind"
        type="button"
        class="palette-item"
        :class="{ 'palette-item--disabled': item.disabled || !localPermissions.canEdit }"
        :disabled="item.disabled || !localPermissions.canEdit"
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
      <div v-if="localValidation.errors.length" class="flash flash--alert">
        <ul><li v-for="(e, i) in localValidation.errors" :key="i">{{ e }}</li></ul>
      </div>
      <div v-if="localValidation.warnings.length" class="flash flash--warn">
        <ul><li v-for="(w, i) in localValidation.warnings" :key="i">{{ w }}</li></ul>
      </div>
      <div v-if="serverErrors.length" class="flash flash--alert">
        <ul><li v-for="(e, i) in serverErrors" :key="i">{{ e }}</li></ul>
      </div>

      <div v-if="!localSteps.length" class="card empty-state">
        <p class="muted">El flujo está vacío. Empezá agregando <strong>Idear</strong>.</p>
      </div>

      <ol class="step-list">
        <template v-for="(step, index) in localSteps" :key="step.id || step.tempId">
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
              'step-card--dragging': draggingIndex === index
            }"
            :draggable="canDrag(step)"
            @dragstart="onDragStart(index, $event)"
            @dragover.prevent="onDragOver(index)"
            @drop.prevent="onDrop(index)"
            @dragend="onDragEnd"
          >
            <!-- La tarjeta entera es el link al módulo (sin panel que abrir,
                 no hay nada más que seleccionar). Sin `id` todavía no hay
                 adónde ir, así que se renderiza como `<span>` en vez de `<a>`.

                 El nombre accesible va EXPLÍCITO: calculado del contenido
                 salía «⠿1PostulaciónIdearIA asistida (heredado)Pendiente»
                 —el compilador de Vue no deja espacio entre spans hermanos,
                 así que el handle decorativo, el índice, el nombre, el tipo,
                 el modo de IA y el chip de estado se leen pegados—. En el
                 `<span>` del módulo sin guardar no va: un genérico con
                 `aria-label` y sin rol esconde su propio contenido. -->
            <component
              :is="stepCardTag(step)"
              class="step-card__link"
              draggable="false"
              :href="step.id ? `/challenges/${localChallenge.slug}/steps/${step.id}` : undefined"
              :aria-label="step.id ? `Configurar «${step.name}»` : null"
            >
              <span class="step-card__handle" :class="{ 'is-hidden': !canDrag(step) }">⠿</span>
              <span class="step-card__index">{{ index + 1 }}</span>

              <span class="step-card__body">
                <span class="step-card__name">{{ step.name }}</span>
                <span v-if="!step.id" class="step-card__unsaved">sin guardar</span>
                <span class="step-card__meta">
                  <span class="step-card__kind">{{ step.kindLabel }}</span>
                  <span class="step-card__ai">{{ aiLabel(step) }}</span>
                </span>
              </span>

              <!-- La clase la manda el server (PipelinePresenter#step_json), sin
                   armarla acá con un template literal: Tailwind escanea texto y
                   lo interpolado no lo ve. Es la misma regla que en el HAML. -->
              <span :class="step.statusClass">
                {{ step.statusLabel }}
              </span>
              <span v-if="step.locked" class="step-card__lock" title="Módulo ya ejecutado">🔒</span>
            </component>

            <button
              v-if="!step.locked && localPermissions.canEdit"
              type="button"
              class="step-card__remove"
              title="Quitar del flujo"
              @click.stop="removeStep(index)"
            >×</button>
          </li>
        </template>
      </ol>
    </section>

    <!-- Barra de acciones -->
    <footer class="builder__actions">
      <span v-if="dirty" class="muted">Hay cambios sin guardar.</span>
      <span v-else-if="savedAt" class="muted">Guardado.</span>
      <span class="builder__spacer"></span>
      <button type="button" class="btn btn-ghost" :disabled="saving" @click="save">
        {{ saving ? 'Guardando…' : 'Guardar flujo' }}
      </button>
      <a v-if="localPermissions.canStart && !dirty && localValidation.valid" class="btn btn-primary" :href="urls.show">
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
    insertionFloor: { type: Number, default: null },
    validation: { type: Object, required: true },
    permissions: { type: Object, required: true },
    urls: { type: Object, required: true }
  },

  data() {
    // LAS PROPS SON EL ESTADO INICIAL, NO EL ESTADO.
    //
    // Vue no hace reactivas las props de la raíz: mutarlas cambia el array
    // pero no redibuja nada. Este componente hacía justo eso —`steps.push`,
    // `steps.splice`, y el reemplazo entero tras guardar— así que agregar,
    // quitar y reordenar módulos mutaban los datos en silencio y la pantalla
    // seguía mostrando lo viejo. El segundo clic en la ✕ de una tarjeta que ya
    // no existía reventaba con «Cannot read properties of undefined».
    //
    // Se copia una vez y se trabaja sobre la copia, igual que las otras dos
    // islas. El server sigue siendo la fuente de verdad al guardar.
    const inicial = JSON.parse(JSON.stringify({
      steps: this.steps, palette: this.palette, challenge: this.challenge,
      validation: this.validation, permissions: this.permissions
    }));

    return {
      localSteps: inicial.steps,
      localPalette: inicial.palette,
      localChallenge: inicial.challenge,
      localValidation: inicial.validation,
      localPermissions: inicial.permissions,
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
    // Índice del primer módulo NO tocado: ahí va la línea de agua.
    firstUnlockedIndex() {
      const index = this.localSteps.findIndex((s) => !s.locked);
      return index === -1 ? this.localSteps.length : index;
    }
  },

  watch: {
    localSteps: {
      deep: true,
      handler() { this.dirty = true; }
    }
  },

  methods: {
    aiLabel(step) {
      const value = step.aiMode || this.localChallenge.aiDefaultMode;
      const mode = this.aiModes.find((m) => m.value === value);
      const label = mode ? mode.label : value;
      return step.aiMode ? label : `${label} (heredado)`;
    },

    // Sin `id` (recién agregado, sin guardar el flujo) no hay pantalla de
    // módulo adonde ir: se renderiza como `<span>`, no como `<a>`.
    stepCardTag(step) { return step.id ? 'a' : 'span'; },

    // La línea de agua solo se dibuja si hay algo tocado y algo por delante.
    showWaterline(index) {
      return index === this.firstUnlockedIndex && index > 0;
    },

    canDrag(step) {
      return this.localPermissions.canEdit && this.localPermissions.canReorder && !step.locked;
    },

    addStep(item) {
      if (item.disabled || !this.localPermissions.canEdit) return;

      const step = {
        id: null,
        tempId: `new-${this.nextTempId++}`,
        kind: item.kind,
        kindLabel: item.label,
        name: item.label,
        status: 'pending',
        statusLabel: 'Pendiente',
        // Literal, como el rótulo de al lado: un módulo recién agregado nace
        // pendiente y el server le manda la suya en cuanto se guarda.
        statusClass: 'status-chip status-chip--pending',
        aiMode: null,
        sourceStepId: null,
        criteriaSetId: null,
        locked: false,
        removable: true
      };

      this.localSteps.push(step);
      this.refreshPalette();
    },

    removeStep(index) {
      this.localSteps.splice(index, 1);
      this.refreshPalette();
    },

    // Los módulos "únicos" (Idear) se deshabilitan cuando ya están en el flujo.
    refreshPalette() {
      const kinds = this.localSteps.map((s) => s.kind);
      this.localPalette.forEach((item) => {
        if (item.singleton) item.disabled = kinds.includes(item.kind);
      });
    },

    onDragStart(index, event) {
      if (!this.canDrag(this.localSteps[index])) {
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

      const [moved] = this.localSteps.splice(from, 1);
      this.localSteps.splice(targetIndex, 0, moved);
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
        lock_version: this.localChallenge.lockVersion,
        steps: this.localSteps.map((s) => ({
          id: s.id,
          kind: s.kind,
          name: s.name,
          aiMode: s.aiMode,
          sourceStepId: s.sourceStepId,
          criteriaSetId: s.criteriaSetId
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
      this.localSteps = body.steps;
      this.localPalette = body.palette;
      this.localChallenge = body.challenge;
      this.localValidation = body.validation;
      this.localPermissions = body.permissions;

      this.$nextTick(() => {
        this.dirty = false;
        this.savedAt = new Date();
      });
    }
  }
};
</script>
