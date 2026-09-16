# frozen_string_literal: true

# Semillas de la maqueta.
#
# Se siembran DOS empresas a propósito. La segunda ("otra") existe para que los
# specs cross-tenant tengan contra qué probar y para que cualquiera pueda
# comprobar a mano que el aislamiento funciona. Sin una segunda empresa, un
# bug de tenencia es invisible.
#
# El seed NUNCA llama al proveedor real: activar módulos en `ai_auto` dispara
# tareas de IA, y con `make seed` eso sería una llamada paga por corrida.
#
# No alcanza con fijar el proveedor acá: las tareas se ENCOLAN y las ejecuta
# Sidekiq, que es otro proceso con su propio FLOW_AI_PROVIDER. Por eso los jobs
# corren inline — así el proveedor de fixtures de esta línea es el que se usa,
# y de paso el seed queda determinista y sin depender de que Sidekiq esté vivo.
Flow::AI.provider = Flow::AI::Providers::Fixture.new
ActiveJob::Base.queue_adapter = :inline

# Todo corre bajo bypass!: el scoping automático no aplica cuando estás
# creando las empresas mismas.

Flow::Tenant.bypass! do
  demo = Company.find_or_create_by!(slug: "demo") { |c| c.name = "Empresa Demo" }
  otra = Company.find_or_create_by!(slug: "otra") { |c| c.name = "Otra Empresa" }

  def upsert_user!(email:, name:, password: Flow::Demo::PASSWORD)
    user = User.find_or_initialize_by(email: email)
    user.name = name
    user.password = password
    user.save!
    Identity.find_or_create_by!(provider: Identity::PASSWORD, uid: email) { |i| i.user = user }
    user
  end

  # La cuenta se llamaba `gestor@demo.test` y tenía rol `admin`: el login lista
  # estas cuentas con su rol para que se entre a ver el producto desde cada
  # uno, y la que se llamaba gestor mandaba al rol equivocado —la única con rol
  # `gestor` es Gina—.
  #
  # Se renombra EN EL LUGAR y no se crea una nueva: `upsert_user!` busca por
  # correo, así que una base ya sembrada quedaría con las dos, y la vieja es
  # autora y evaluadora del desafío —borrarla se llevaría sus ideas—. La
  # identidad va con ella: su `uid` es el correo, y dejarla mantendría abierto
  # el login viejo.
  #
  # Es una migración de datos, no parte del seed: se puede borrar en cuanto no
  # queden bases sembradas antes del 16-09-2026.
  vieja = User.find_by(email: "gestor@demo.test")
  if vieja
    vieja.update!(email: "admin2@demo.test")
    Identity.where(provider: Identity::PASSWORD, uid: "gestor@demo.test")
            .update_all(uid: "admin2@demo.test")
  end

  people = {
    "admin@demo.test" => ["Ana Admin", "admin"],
    "admin2@demo.test" => ["Gabriel Gómez", "admin"],
    "eval1@demo.test" => ["Elena Evaluadora", "evaluator"],
    "eval2@demo.test" => ["Emilio Evaluador", "evaluator"],
    "part1@demo.test" => ["Paula Participante", "participant"],
    "part2@demo.test" => ["Pedro Participante", "participant"],
    "guia@demo.test" => ["Gina Guía", "gestor"]
  }

  people.each do |email, (name, role)|
    user = upsert_user!(email: email, name: name)
    Membership.find_or_create_by!(company: demo, user: user) { |m| m.role = role }
  end

  # Empresa espejo, con su propia gente. Ningún usuario cruza entre las dos:
  # así un 200 donde debería haber 404 salta a la vista.
  otra_admin = upsert_user!(email: "admin@otra.test", name: "Olga Otra")
  Membership.find_or_create_by!(company: otra, user: otra_admin) { |m| m.role = "admin" }

  # Gina acompaña a las DOS empresas: es el caso que justifica el rol. Una
  # membresía en cada una, y el aislamiento lo garantiza Current.company —
  # nunca ve las dos a la vez, y las FKs compuestas hacen imposible mezclar.
  gina = User.find_by!(email: "guia@demo.test")
  Membership.find_or_create_by!(company: otra, user: gina) { |m| m.role = "gestor" }

  # Una persona con acceso a las dos empresas: ejercita el selector post-login.
  multi = upsert_user!(email: "multi@demo.test", name: "Marta Multiempresa")
  Membership.find_or_create_by!(company: demo, user: multi) { |m| m.role = "admin" }
  Membership.find_or_create_by!(company: otra, user: multi) { |m| m.role = "admin" }

  # ── Desafío de ejemplo, recorrido completo ────────────────────────────
  #
  # Se ejecuta el flujo entero para que la maqueta abra con datos reales en
  # cada pantalla: ideas con versiones, feedback atendido y sin atender,
  # evaluaciones de dos rondas, un corte con eliminadas y el tablero final.
  Flow::Tenant.with(demo) do
    Challenge.where(slug: "merma-bodega").destroy_all
    # El seed se corre varias veces: los sets de la biblioteca no cuelgan del
    # desafío, así que se limpian aparte o quedan duplicados.
    CriteriaSet.library.where(name: "Evaluación técnica").destroy_all

    challenge = Challenge.create!(
      slug: "merma-bodega",
      name: "Reducir la merma en bodega",
      brief: "La merma en bodega creció 18% interanual. Buscamos ideas que la reduzcan " \
             "sin agregar dotación y que se puedan pilotear en un centro antes de fin de año.",
      ai_default_mode: "ai_assisted"
    )

    # Un set de criterios de la biblioteca, para que el desafío no corra con
    # los criterios por defecto. Mezcla los dos ejes a propósito: dos que
    # puntúa una persona, uno que verifica el sistema, y uno derivado.
    tecnicos = CriteriaSet.create!(name: "Evaluación técnica", scope: "library",
                                   description: "Impacto contra esfuerzo, con la idea completa como requisito.")
    [
      { name: "Impacto", key: "impacto", weight: 0.4, source: "manual", scale_type: "numeric",
        description: "Cuánto baja la merma si funciona.",
        scale_config: { "min" => 1, "max" => 10, "step" => 1, "direction" => "higher_better" } },
      { name: "Esfuerzo", key: "esfuerzo", weight: 0.25, source: "manual", scale_type: "numeric",
        description: "Cuánto cuesta implementarla.",
        scale_config: { "min" => 1, "max" => 10, "step" => 1, "direction" => "lower_better" } },
      { name: "Está desarrollada", key: "desarrollada", weight: 0.15, source: "automatic",
        scale_type: "boolean",
        source_config: { "check" => "field_present", "field_key" => "solucion", "min_length" => 120 } },
      { name: "Prioridad", key: "prioridad", weight: 0.2, source: "formula", scale_type: "numeric",
        description: "Impacto sobre esfuerzo.",
        scale_config: { "expression" => "impacto / esfuerzo", "output" => { "min" => 0, "max" => 10 } } }
    ].each_with_index { |attrs, index| tecnicos.criteria.create!(**attrs, position: index) }
    tecnicos.refresh_status!

    # Filtros del corte: condiciones de sí/no que la idea tiene que cumplir
    # para seguir. No dan puntaje —eso lo trae la evaluación previa— sino que
    # habilitan o dejan afuera.
    filtros = CriteriaSet.create!(name: "Filtros de pase a comité", scope: "library",
                                  description: "Lo mínimo para que valga la pena discutirla en comité.")
    [
      { name: "El problema está claro", key: "problema_claro", weight: 0.5, source: "manual",
        scale_type: "boolean", description: "Se entiende qué se resuelve, para quién y con qué costo hoy." },
      { name: "El piloto está acotado", key: "piloto_acotado", weight: 0.5, source: "ai",
        scale_type: "boolean", description: "Define alcance y plazo, en vez de un despliegue completo." }
    ].each_with_index { |attrs, index| filtros.criteria.create!(**attrs, position: index) }
    filtros.refresh_status!

    pipeline = challenge.pipeline
    [
      ["ideation",   "Postulación de ideas",  { "min_ideas" => 3 },                          nil],
      ["evolution",  "Ronda de feedback",     {},                                            "ai_assisted"],
      ["evaluation", "Evaluación técnica",    { "min_assessments" => 2 },                    "human"],
      ["selection",  "Corte a top 3",         { "cut" => { "mode" => "top_n", "value" => 3 } }, "human"],
      ["evaluation", "Evaluación de comité",  { "min_assessments" => 3 },                    "human"],
      ["selection",  "Finalistas",            { "cut" => { "mode" => "top_n", "value" => 2 } }, "human"],
      ["reporting",  "Reporte de cierre",     { "mode" => "by_version" },                    "ai_auto"]
    ].each do |kind, name, config, ai_mode|
      set = tecnicos if name == "Evaluación técnica"
      set = filtros if name == "Corte a top 3"
      pipeline.insert(kind: kind, after: :end, name: name, config: config, ai_mode: ai_mode,
                      criteria_set: set)
    end

    admin = User.find_by!(email: "admin@demo.test")
    autores = User.where(email: %w[part1@demo.test part2@demo.test admin2@demo.test]).to_a
    evaluadores = User.where(email: %w[eval1@demo.test eval2@demo.test admin2@demo.test]).to_a

    # El formulario lo define el dueño del desafío antes de arrancar: sin
    # preguntas nadie puede postular y `start!` no deja abrir el módulo.
    ideation = pipeline.ideation_step
    [
      ["titulo", "Título", "text", { "is_title" => true }, "Una frase que identifique la idea."],
      ["problema", "¿Qué problema resuelve?", "textarea", {}, "La situación actual y su costo."],
      ["solucion", "¿Cómo funcionaría?", "textarea", {}, "Qué se hace y quién lo hace."],
      ["costeo", "Costeo estimado", "file", {}, "Una planilla o un PDF con los números, si los tenés."]
    ].each_with_index do |(key, label, type, config, hint), index|
      ideation.form_fields.create!(key: key, label: label, field_type: type, hint: hint,
                                   required: type != "file", position: index, config: config)
    end

    pipeline.start!
    ideation.reload

    semillas = [
      ["Sensores de peso por rack",
       "Nadie sabe en qué punto de la bodega se pierde producto: el inventario cuadra al ingreso y no al despacho.",
       "Instalar celdas de carga en los racks críticos y comparar el peso esperado contra el real cada turno."],
      ["Doble verificación en el picking",
       "El 60% de las diferencias aparece en picking, donde una sola persona arma y valida el pedido.",
       "Que un segundo operario escanee el pedido armado antes de sellarlo. Piloto en un centro por dos meses."],
      ["Rotación FEFO automática",
       "Se vence producto en la parte de atrás de los racks porque la reposición carga adelante.",
       "Que el WMS asigne ubicación por fecha de vencimiento y bloquee el picking del lote más nuevo."],
      ["Cámaras en zona de merma",
       "La merma declarada no coincide con la observada en los conteos cíclicos.",
       "Cámaras en la zona de descarte con revisión semanal por muestreo."],
      ["Tablero de merma por turno",
       "La merma se reporta mensual, cuando ya no se puede actuar sobre la causa.",
       "Tablero con la merma del turno anterior visible en la bodega al empezar cada jornada."]
    ]

    ideas = semillas.each_with_index.map do |(titulo, problema, solucion), index|
      idea = Idea.create!(challenge: challenge, author: autores[index % autores.size],
                          status: "draft", origin: index == 4 ? "ai" : "human")

      Flow::Ideas::PublishVersion.new(
        idea, payload: { "titulo" => titulo, "problema" => problema, "solucion" => solucion },
        author: idea.author, actor_type: idea.origin, source_step: ideation,
        change_note: "Creación de la idea"
      ).call

      idea.update!(submitted_at: Time.current)
      idea
    end

    # Dos ideas hechas entre varias personas, y una con su costeo adjunto.
    # `autores` y `evaluadores` comparten a admin2@demo.test, así que se elige
    # contra el autor real de cada idea en vez de por índice.
    sumar = lambda do |idea, role, candidatos|
      persona = candidatos.find { |u| u.id != idea.author_id }
      IdeaContributor.create!(idea: idea, user: persona, role: role) if persona
    end

    sumar.call(ideas[0], "contributor", autores)
    sumar.call(ideas[0], "sponsor", evaluadores.reject { |u| autores.include?(u) })
    sumar.call(ideas[3], "reviewer", autores.reverse)

    adjunto = ideas[0].current_version.attachments.create!(field_key: "costeo")
    adjunto.file.attach(
      io: StringIO.new("Costeo del piloto\nCeldas de carga (12 racks): 4.200.000 CLP\nInstalación: 900.000 CLP\n"),
      filename: "costeo-sensores.txt", content_type: "text/plain"
    )

    # Gina acompaña ESTE desafío. No ve el otro de la misma empresa: tener
    # membresía dejó de ser sinónimo de ver todo lo suyo.
    ChallengeGestor.find_or_create_by!(challenge: challenge,
                                       user: User.find_by!(email: "guia@demo.test"))

    pipeline.advance!  # → Ronda de feedback
    evolution = pipeline.active_step

    # Feedback humano sobre las dos primeras, que después lo atienden.
    [
      [ideas[0], "question", "¿Cuál es el costo estimado y en cuánto se recupera? Sin eso el comité no puede compararla."],
      [ideas[1], "suggestion", "Acotá el piloto a un centro y definí qué métrica tiene que moverse para considerarlo exitoso."],
      [ideas[3], "issue", "Hay que revisar el tema de privacidad antes de avanzar con cámaras en zona de trabajo."]
    ].each do |idea, kind, body|
      FeedbackItem.create!(challenge_step: evolution, idea: idea,
                           idea_version_id: idea.current_version_id,
                           author: admin, kind: kind, body: body)
    end

    # Dos autores responden publicando versiones nuevas.
    respuestas = {
      ideas[0] => ["Sensores de peso por rack (piloto acotado)",
                   "Instalar celdas de carga en los racks críticos y comparar el peso esperado contra el real " \
                   "cada turno. Se acota el piloto a un solo centro. Costo estimado: 8 celdas de carga y dos " \
                   "semanas de integración; se recupera con evitar el 15% de la merma actual.",
                   "Agregué el costo estimado que pidió el comité"],
      ideas[1] => ["Doble verificación en el picking",
                   "Que un segundo operario escanee el pedido armado antes de sellarlo. Piloto en un centro por " \
                   "dos meses, con la diferencia de inventario como métrica de éxito.",
                   "Acoté el alcance y definí la métrica"]
    }

    respuestas.each do |idea, (titulo, solucion, nota)|
      version = Flow::Ideas::PublishVersion.new(
        idea,
        payload: idea.payload.merge("titulo" => titulo, "solucion" => solucion),
        author: idea.author, source_step: evolution, change_note: nota
      ).call.version
      evolution.handler.record_response!(idea, version)
    end

    pipeline.advance!  # → Evaluación técnica

    # ── Helper para evaluar un módulo completo ──
    evaluar = lambda do |step, jueces, base_por_idea|
      handler = step.handler
      step.step_entries.includes(:idea).each_with_index do |entry, i|
        jueces.each_with_index do |juez, j|
          assessment = step.assessments.create!(
            idea: entry.idea, idea_version_id: entry.idea.current_version_id,
            evaluator: juez, status: "submitted", submitted_at: Time.current,
            overall_comment: j.zero? ? "Evaluada sobre #{entry.idea.current_version.label}." : nil
          )
          # Solo los criterios que alguien responde. Los automáticos y las
          # fórmulas los calcula ScoreAssessment: ponerles una nota a mano
          # sería inventar lo que el sistema tiene que deducir.
          answerable = handler.criteria_snapshot.select { |c| %w[manual ai].include?(c["source"]) }
          answerable.each_with_index do |config, k|
            criterion = Criterion.find(config["id"])
            base = base_por_idea[i][k] || base_por_idea[i].last
            raw = [[base + (j - 1), 1].max, 10].min
            numeric, normalized = criterion.score(raw)
            assessment.assessment_scores.create!(
              criterion_id: criterion.id, criterion_key: config["key"], weight_used: config["weight"],
              raw_value: raw.to_s, numeric_value: numeric, normalized_value: normalized
            )
          end
          Flow::Evaluation::ScoreAssessment.new(assessment, criteria_snapshot: handler.criteria_snapshot).call
        end
        handler.recompute_entry!(entry)
      end
    end

    evaluar.call(pipeline.active_step, evaluadores, [[9, 8, 3], [8, 7, 4], [6, 6, 5], [4, 5, 7], [7, 8, 2]])
    pipeline.advance!  # → Corte a top 3

    corte = pipeline.active_step

    # Los filtros se responden idea por idea. Uno lo responde la IA —queda su
    # ai_run y su justificación, igual que una evaluación automática— y el
    # resto los responde el comité. Una idea queda afuera acá: el filtro es lo
    # que la deja fuera, no el puntaje.
    Flow::AI::Runner.call(
      Flow::AI::Tasks::DecideVerdicts.new(challenge: challenge, step: corte, idea: ideas[0]),
      mode: "ai_auto", challenge: challenge, step: corte, idea: ideas[0], requested_by: admin
    )

    veredictos_humanos = {
      ideas[1] => [["problema_claro", true, "El 60% de las diferencias en picking está medido."],
                   ["piloto_acotado", true, "Un centro, dos meses, con métrica de éxito definida."]],
      ideas[2] => [["problema_claro", true, "El vencimiento por reposición adelante es un problema real."],
                   ["piloto_acotado", false, "Cambia la asignación del WMS para toda la operación: no hay piloto."]],
      ideas[3] => [["problema_claro", true, "La diferencia entre merma declarada y observada está documentada."],
                   ["piloto_acotado", true, "Zona de descarte, revisión semanal por muestreo."]],
      ideas[4] => [["problema_claro", true, "Reportar mensual impide actuar sobre la causa."],
                   ["piloto_acotado", true, "Un tablero por turno, sin dependencias externas."]]
    }

    veredictos_humanos.each do |idea, filas|
      filas.each do |key, passed, note|
        corte.handler.record_verdict!(idea: idea, criterion_key: key, passed: passed,
                                      decided_by: admin, note: note)
      end
    end

    corte.handler.decide!(
      corte.handler.ranking.select(&:above_cut?).map { |row| row.idea.id },
      decided_by: admin,
      reason: "El comité priorizó lo que se puede pilotear este trimestre"
    )
    pipeline.advance!  # → Evaluación de comité

    comite = pipeline.active_step

    # En el comité no todas las voces pesan igual: quien lidera técnicamente
    # cuenta doble. Es lo que la columna `weight` soportó siempre y no entraba
    # en ninguna cuenta.
    StepAssignment.find_by(challenge_step_id: comite.id, user_id: evaluadores.first.id)
                  &.update!(weight: 2)

    evaluar.call(comite, evaluadores, [[9, 8, 4], [7, 8, 3], [6, 7, 5]])
    pipeline.advance!  # → Finalistas

    finalistas = pipeline.active_step
    finalistas.handler.decide!(
      finalistas.handler.ranking.select(&:above_cut?).map { |row| row.idea.id },
      decided_by: admin, reason: "Las dos que entran al presupuesto del trimestre"
    )
    pipeline.advance!  # → Reporte de cierre

    reporte = pipeline.active_step
    Flow::AI::Runner.call(
      Flow::AI::Tasks::SummarizeChallenge.new(challenge: challenge, step: reporte),
      mode: "ai_auto", challenge: challenge, step: reporte, requested_by: admin
    )

    # Un segundo desafío EN BORRADOR: así el builder se puede editar libremente
    # y se ve el contraste con el que ya arrancó.
    Challenge.where(slug: "onboarding-remoto").destroy_all
    borrador = Challenge.create!(
      slug: "onboarding-remoto",
      name: "Mejorar el onboarding remoto",
      brief: "Las primeras dos semanas de alguien que entra remoto son confusas: no sabe a quién " \
             "preguntar ni qué se espera de él. Buscamos ideas para que la primera quincena sea clara.",
      ai_default_mode: "ai_assisted"
    )

    # A propósito SIN formulario: es el estado en que nace un desafío. El
    # builder lo marca como error y la pantalla del formulario ofrece las dos
    # salidas (los básicos, o pedírselo a la IA).
    [["ideation", "Postulación"], ["evaluation", "Primera revisión"]].each do |kind, name|
      borrador.pipeline.insert(kind: kind, after: :end, name: name)
    end

    # Un desafío en BORRADOR y sin formulario, para las capturas que verifican
    # ese estado.
    #
    # Tiene el suyo propio y no comparte el de arriba a propósito: cuando las
    # capturas dependían de un desafío que además se usa para probar a mano,
    # bastaba con que alguien le aplicara una propuesta de IA para que la
    # corrida fallara por datos y no por código. Pasó dos veces.
    #
    # Tiene los CINCO `kind` pendientes —no solo idear y evaluación— porque
    # las capturas de «las dos caras» recorren la cara de configuración de
    # cada tipo de módulo, y esa cara de evaluación/evolución pendiente no
    # tenía ningún desafío sembrado que la ofreciera.
    Challenge.where(slug: "sin-formulario").destroy_all
    sin_formulario = Challenge.create!(
      slug: "sin-formulario",
      name: "Ideas para el comedor",
      brief: "El comedor se llena entre las 13 y las 14 y la fila desalienta a media planta. " \
             "Buscamos ideas para repartir la demanda sin ampliar el espacio.",
      ai_default_mode: "ai_assisted"
    )
    [
      ["ideation", "Postulación"],
      ["evolution", "Ronda de feedback"],
      ["evaluation", "Primera revisión"],
      ["selection", "Selección para pilotear"],
      ["reporting", "Reporte de cierre"]
    ].each do |kind, name|
      sin_formulario.pipeline.insert(kind: kind, after: :end, name: name)
    end

    # El de selección se siembra con un set INLINE de verdad —no de la
    # biblioteca—: la captura `09-12-criterios-del-modulo` fotografía el
    # editor de criterios embebido, y ese editor solo monta con un set propio
    # (`step.criteria_set&.library? ? nil : step.criteria_set` en
    # `steps/_criterios_editor.html.haml`). Va en el de SELECCIÓN y no en el
    # de evaluación: ese último lo usa `03d-paso-a-paso-criterios` para
    # verificar justo el estado VACÍO («Usar los tres genéricos…») — ponerle
    # criterios propios ahí le taparía lo que esa captura prueba.
    seleccion = sin_formulario.pipeline.steps.find { |s| s.kind == "selection" }
    filtros_comedor = CriteriaSet.create!(
      name: "Criterios de «#{seleccion.name}»", scope: "inline", owner_step_id: seleccion.id,
      description: "Condiciones mínimas para que una idea se pueda pilotear en el comedor."
    )
    [
      { name: "No requiere obra", key: "sin_obra", weight: 0.5, source: "manual",
        scale_type: "boolean", description: "Se puede probar sin modificar el espacio físico." },
      { name: "Piloteable en dos semanas", key: "piloteable_dos_semanas", weight: 0.5, source: "manual",
        scale_type: "boolean", description: "Se arma un piloto en menos de dos semanas." }
    ].each_with_index { |attrs, index| filtros_comedor.criteria.create!(**attrs, position: index) }
    filtros_comedor.refresh_status!
    seleccion.update!(criteria_set_id: filtros_comedor.id)

    # Un desafío EN CURSO que existe sólo para `make screens`, donde se
    # fotografían los dos popups de la IA.
    #
    # Propio y no compartido, como manda CLAUDE.md: cuando las capturas
    # dependieron de un desafío que además se usa a mano, bastó con que alguien
    # le aplicara una propuesta para que la corrida fallara por datos. Pasó dos
    # veces. `sin-formulario` tampoco sirve: está en borrador y sin ideas, y
    # darle ideas le cambiaría lo que fotografían sus otras capturas.
    #
    # Idear ABIERTO y en modo asistido, con dos ideas postuladas: hace falta
    # que haya al menos dos para que «Detectar duplicados» tenga contra qué
    # comparar.
    Challenge.where(slug: "recorrido-ia").destroy_all
    recorrido = Challenge.create!(
      slug: "recorrido-ia",
      name: "Menos papel en la operación",
      brief: "Cada despacho se imprime tres veces y nadie vuelve a mirar esas copias. " \
             "Buscamos ideas para sacar el papel del circuito sin perder la trazabilidad.",
      ai_default_mode: "ai_assisted"
    )
    recorrido.pipeline.insert(kind: "ideation", after: :end, name: "Postulación")
    recorrido.pipeline.insert(kind: "evolution", after: :end, name: "Ronda de feedback")
    recorrido_ideacion = recorrido.pipeline.ideation_step
    [
      ["titulo", "Título", "text", { "is_title" => true }, "Una frase que identifique la idea."],
      ["problema", "¿Qué problema resuelve?", "textarea", {}, "La situación actual y su costo."],
      ["solucion", "¿Cómo funcionaría?", "textarea", {}, "Qué se hace y quién lo hace."]
    ].each_with_index do |(key, label, type, config, hint), index|
      recorrido_ideacion.form_fields.create!(key: key, label: label, field_type: type, hint: hint,
                                             required: true, position: index, config: config)
    end
    recorrido.pipeline.start!
    recorrido_ideacion.reload

    [
      ["Guía de despacho digital",
       "Cada despacho se imprime tres veces y las copias terminan en una caja que nadie revisa.",
       "Firmar la guía en el celular del chofer y guardar el PDF contra el número de despacho."],
      ["Firma en el celular del transportista",
       "El papel sale de bodega sólo para que alguien firme, y después vuelve para archivarse.",
       "Que el transportista firme en una app y que el sistema cierre el despacho con esa firma."]
    ].each do |titulo, problema, solucion|
      idea = Idea.create!(challenge: recorrido, author: User.find_by!(email: "part1@demo.test"),
                          status: "draft", origin: "human")
      Flow::Ideas::PublishVersion.new(
        idea, payload: { "titulo" => titulo, "problema" => problema, "solucion" => solucion },
        author: idea.author, actor_type: "human", source_step: recorrido_ideacion,
        change_note: "Creación de la idea"
      ).call
      idea.update!(submitted_at: Time.current)
    end

    # Un desafío SIN módulos, para la captura del selector de plantillas.
    # Antes el script de capturas creaba uno en cada corrida y no lo borraba:
    # la base de desarrollo terminó con dieciséis «desafio-de-prueba-N».
    Challenge.where(slug: "sin-armar").destroy_all
    Challenge.create!(
      slug: "sin-armar",
      name: "Programa de mejora continua",
      brief: "Queremos un canal permanente para que cualquiera proponga mejoras al proceso " \
             "de su área, con revisión mensual.",
      ai_default_mode: "ai_assisted"
    )

    puts "Desafío en curso:  #{challenge.name}"
    puts "  módulos:   #{challenge.steps.count} · activo: #{challenge.pipeline.active_step&.name}"
    puts "  ideas:     #{challenge.ideas.count} (#{challenge.ideas.alive.count} en carrera)"
    puts "  versiones: #{IdeaVersion.where(idea_id: challenge.ideas.select(:id)).count}"
    puts "  feedback:  #{FeedbackItem.where(idea_id: challenge.ideas.select(:id)).count}"
    puts "  notas:     #{Assessment.where(idea_id: challenge.ideas.select(:id)).count}"
    puts "  decisiones: #{SelectionDecision.where(idea_id: challenge.ideas.select(:id)).count}"
    puts "Desafío en borrador: Mejorar el onboarding remoto"
    puts "Desafío del recorrido: #{recorrido.name} (#{recorrido.ideas.count} ideas)"
  end

  puts ""
  puts "Empresas:    #{Company.count}"
  puts "Usuarios:    #{User.count}"
  puts "Membresías:  #{Membership.count}"
  puts ""
  puts "  Login demo:  admin@demo.test / #{Flow::Demo::PASSWORD}"
  puts "  Multiempresa: multi@demo.test / #{Flow::Demo::PASSWORD}"
end
