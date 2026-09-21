# frozen_string_literal: true

require "rails_helper"

# La cara de ejecución de un módulo en tres zonas: el trabajo al centro, lo
# que se consulta a la derecha (`.app-aside`) y los ajustes plegados al final
# (`.ajustes`). Es markup, no permisos: mudar un bloque de lugar no puede
# sacarlo de atrás de su guarda, y un spec que solo mira a quien administra no
# lo ve. Por eso cada zona se prueba por rol.
RSpec.describe "la pantalla del módulo en tres zonas", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:elena) { member("elena@test.dev", :evaluator) }
  let!(:paula) { member("paula@test.dev", :participant) }

  def paso(kind) = as_company(company) { challenge.steps.reload.find { |s| s.kind == kind } }

  def documento = Nokogiri::HTML(response.body)

  # El texto de cada zona, leído del HTML servido.
  def zonas
    { referencia: documento.at_css(".app-aside")&.text.to_s,
      ajustes: documento.at_css(".ajustes")&.text.to_s }
  end

  # La columna de referencia es una zona de CONSULTA colgada del `%h1` de la
  # pantalla, y sus tarjetas van todas en `h3`: el `h2` es de las tarjetas del
  # centro, que es el trabajo. `.section-title` define tamaño, peso y color por
  # clase y no por etiqueta, así que un nivel desparejo no se ve en pantalla ni
  # lo agarra `make screens` — sólo desordena el outline, que es justamente lo
  # que usa quien navega con lector de pantalla.
  def titulos_de_mas_en_la_referencia
    documento.css(".app-aside h1, .app-aside h2").map { |n| "#{n.name}: #{n.text.strip}" }
  end

  def postular!(challenge, author:, titulo:)
    as_company(company) do
      i = create(:idea, challenge: challenge, author: author)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => titulo }, author: author).call
      i.update!(submitted_at: Time.current)
      i
    end
  end

  describe "evaluación" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", config: { "min_assessments" => 1 })
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
      end
    end

    it "quien administra: consulta a la derecha y los ajustes plegados" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Criterios", "Quién evalúa", elena.name, "Cómo quedó configurado")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA", "Peso")
      expect(documento.at_css(".ajustes details.ajustes__plegable")).not_to be_nil
      expect(titulos_de_mas_en_la_referencia).to be_empty
    end

    it "quien evalúa: la referencia sin la lista de asignaciones, y sin ajustes" do
      sign_in(elena, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Criterios", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quién evalúa")
      expect(documento.at_css(".ajustes")).to be_nil
    end

    it "quien participa: tampoco ve asignaciones ni ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(zonas[:referencia]).to include("Progreso", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quién evalúa")
      expect(documento.at_css(".ajustes")).to be_nil
    end

    # La pantalla del módulo terminó de migrar: ningún `.panel` servido. Las
    # tarjetas de adentro de una isla no están en el HTML del servidor.
    it "no sirve ningún panel viejo" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
    end

    describe "el desglose por fila" do
      before do
        as_company(company) do
          evaluacion = challenge.steps.reload.find(&:evaluation?)
          idea = challenge.ideas.first
          evaluacion.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                                         evaluator: elena, actor_type: "human", status: "submitted",
                                         submitted_at: Time.current, normalized_score: 0.58,
                                         overall_comment: "Falta el costo del piloto")
          evaluacion.handler.recompute_entry!(StepEntry.find_by(challenge_step_id: evaluacion.id, idea_id: idea.id))
        end
      end

      it "quien administra despliega la fila y ve quién puso qué" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("evaluation"))

        desglose = documento.at_css("details.fila-de-idea__plegable .fila-de-idea__desglose")
        expect(desglose&.text.to_s).to include(elena.name, "Falta el costo del piloto")
        expect(response.body).not_to include("Evaluaciones hechas")
      end

      it "«Evaluar» queda afuera del summary: un clic ahí no despliega la fila" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("evaluation"))

        # El link del título sí va adentro del summary: navega, no despliega.
        # Lo que no puede ir es un formulario ni las acciones de la fila.
        expect(documento.css("summary form, summary .fila-de-idea__acciones")).to be_empty
      end

      it "quien participa no tiene fila desplegable ni ve quién evaluó" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("evaluation"))

        expect(documento.at_css(".fila-de-idea__plegable")).to be_nil
        expect(response.body).not_to include(elena.name)
      end
    end
  end

  describe "selección" do
    # Un grupo por escenario y no un `before` suelto, como en reportería: el
    # registro de decisiones necesita dos ideas y el corte ya confirmado, y un
    # `before` de afuera corre también para los grupos de adentro.
    describe "las zonas" do
      let!(:challenge) do
        as_company(company) do
          c = create(:challenge, name: "Merma", ai_default_mode: "human")
          seed_form!(c.steps.create!(kind: "ideation", position: 1))
          # Sin evaluación antes, la selección arranca solo con el orden manual:
          # si no, `start!` falla y la pantalla sirve la cara de configuración.
          c.steps.create!(kind: "selection", position: 2, name: "Corte",
                          config: { "score_source" => { "type" => "manual" } })
          c
        end
      end

      before do
        postular!(challenge, author: paula, titulo: "Sensores")
        as_company(company) do
          challenge.pipeline.start!
          challenge.pipeline.advance!
          expect(paso("selection")).to be_active
        end
      end

      # Selección no tiene referencia: con la columna puesta el ranking no entra
      # en el centro. «Cómo se decide» va arriba de la tabla.
      it "quien administra: cómo se decide sin columna de referencia, los ajustes plegados" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("selection"))

        expect(response.body).to include("Cómo se decide")
        expect(documento.at_css(".app-aside")).to be_nil
        expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA")
        expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
      end

      it "quien participa: cómo se decide, sin ajustes" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("selection"))

        expect(response.body).to include("Cómo se decide")
        expect(documento.at_css(".app-aside")).to be_nil
        expect(documento.at_css(".ajustes")).to be_nil
      end
    end

    # El registro de decisiones dice, idea por idea, si avanzó y en qué puesto:
    # es la misma lista que el ranking de arriba, y se filtra igual con
    # `@ideas_visibles`. Quien decidió, cuándo y el motivo de la tanda siguen a
    # la vista de todos —es lo que explica por qué la idea de uno avanzó o no—.
    describe "el registro de decisiones" do
      let!(:pedro) { member("pedro@test.dev", :participant) }

      let!(:challenge) do
        as_company(company) do
          c = create(:challenge, name: "Merma", ai_default_mode: "human")
          seed_form!(c.steps.create!(kind: "ideation", position: 1))
          c.steps.create!(kind: "selection", position: 2, name: "Corte",
                          config: { "score_source" => { "type" => "manual" } })
          c
        end
      end

      before do
        de_paula = postular!(challenge, author: paula, titulo: "Sensores de peso")
        postular!(challenge, author: pedro, titulo: "Cámaras en la merma")
        as_company(company) do
          challenge.pipeline.start!
          challenge.pipeline.advance!
          paso("selection").handler.decide!([de_paula.id], decided_by: admin,
                                            reason: "El comité priorizó impacto sobre esfuerzo")
        end
      end

      def registro
        documento.css(".app-main .card")
                 .find { |c| c.at_css(".section-title")&.text.to_s.include?("Registro de decisiones") }
      end

      it "quien participa ve su fila y el motivo de la tanda, no las ajenas" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("selection"))

        expect(registro.text).to include("Sensores de peso", "El comité priorizó impacto sobre esfuerzo")
        expect(registro.text).not_to include("Cámaras en la merma")
      end

      it "quien administra ve las dos" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("selection"))

        expect(registro.text).to include("Sensores de peso", "Cámaras en la merma")
      end
    end
  end

  describe "evolución" do
    let!(:gina) { member("gina@test.dev", :gestor) }

    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
        c
      end
    end

    before do
      postular!(challenge, author: paula, titulo: "Sensores")
      as_company(company) do
        challenge.pipeline.start!
        challenge.pipeline.advance!
        expect(paso("evolution")).to be_active
      end
    end

    it "quien administra: progreso y quiénes acompañan a la derecha, gestores en los ajustes" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evolution"))

      expect(zonas[:referencia]).to include("Progreso", "Quiénes acompañan", "Cómo quedó configurado")
      expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA", "Elegí a quién sumar")
      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
      expect(titulos_de_mas_en_la_referencia).to be_empty
    end

    it "quien participa: sin quiénes acompañan y sin ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("evolution"))

      expect(zonas[:referencia]).to include("Progreso", "Cómo quedó configurado")
      expect(zonas[:referencia]).not_to include("Quiénes acompañan")
      expect(documento.at_css(".ajustes")).to be_nil
    end
  end

  describe "reportería" do
    # Un grupo propio y no el `before` suelto de `reportería`: un `before` de
    # afuera corre también para los grupos de adentro, y el desafío de «lo que
    # ve cada quien» tiene otro flujo.
    describe "las zonas" do
      let!(:challenge) do
        as_company(company) do
          c = create(:challenge, name: "Merma", ai_default_mode: "human")
          seed_form!(c.steps.create!(kind: "ideation", position: 1))
          c.steps.create!(kind: "reporting", position: 2, name: "Informe")
          c
        end
      end

      before do
        postular!(challenge, author: paula, titulo: "Sensores")
        as_company(company) do
          challenge.pipeline.start!
          challenge.pipeline.advance!
          expect(paso("reporting")).to be_active
        end
      end

      it "quien administra: configuración y descargas a la derecha, el reporte al centro" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(zonas[:referencia]).to include("Cómo quedó configurado", "Descargas", "Excel", "PDF")
        expect(zonas[:referencia]).not_to include("Embudo")
        expect(zonas[:ajustes]).to include("Ajustes del módulo", "Modo de IA")
        expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
        expect(titulos_de_mas_en_la_referencia).to be_empty
      end
    end

    describe "lo que ve cada quien" do
      let!(:pedro) { member("pedro@test.dev", :participant) }

      let!(:challenge) do
        as_company(company) do
          c = create(:challenge, name: "Merma", ai_default_mode: "human")
          seed_form!(c.steps.create!(kind: "ideation", position: 1))
          c.steps.create!(kind: "evaluation", position: 2, name: "Técnica", config: { "min_assessments" => 1 })
          c.steps.create!(kind: "reporting", position: 3, name: "Informe")
          c
        end
      end

      before do
        postular!(challenge, author: paula, titulo: "Sensores de peso")
        postular!(challenge, author: pedro, titulo: "Cámaras en la merma")
        as_company(company) do
          challenge.pipeline.start!
          challenge.pipeline.advance!
          evaluacion = challenge.steps.reload.find(&:evaluation?)
          challenge.ideas.each do |idea|
            evaluacion.assessments.create!(idea: idea, idea_version_id: idea.current_version_id,
                                           evaluator: elena, actor_type: "human", status: "submitted",
                                           submitted_at: Time.current, normalized_score: 0.6)
            evaluacion.handler.recompute_entry!(StepEntry.find_by(challenge_step_id: evaluacion.id, idea_id: idea.id))
          end
          challenge.pipeline.advance!
          informe = challenge.steps.reload.find(&:reporting?)
          # Un resumen narrativo listo, que nombra una idea ajena a quien participa.
          Report.create!(challenge_step: informe, kind: "narrative", format: "dashboard", status: "ready",
                         data: { "summary" => "«Cámaras en la merma» quedó última por esfuerzo." })
        end
        expect(paso("reporting")).to be_active
      end

      def tarjeta(titulo) = documento.css(".app-main .card").find { |c| c.at_css(".section-title")&.text.to_s.include?(titulo) }

      it "quien participa: lo agregado y sus ideas, sin resumen ni descargas" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(tarjeta("Embudo")).not_to be_nil
        expect(tarjeta("Ranking").text).to include("Sensores de peso")
        expect(tarjeta("Ranking").text).not_to include("Cámaras en la merma")
        expect(tarjeta("Matriz por módulo").text).not_to include("Cámaras en la merma")
        expect(response.body).not_to include("quedó última por esfuerzo")
        expect(zonas[:referencia]).not_to include("Descargas")
      end

      it "quien evalúa: el pool entero, sin descargas ni pedido a la IA" do
        sign_in(elena, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(tarjeta("Ranking").text).to include("Sensores de peso", "Cámaras en la merma")
        expect(response.body).to include("quedó última por esfuerzo")
        expect(zonas[:referencia]).not_to include("Descargas")
      end

      it "quien administra: todo" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("reporting"))

        expect(tarjeta("Ranking").text).to include("Sensores de peso", "Cámaras en la merma")
        expect(response.body).to include("quedó última por esfuerzo")
        expect(zonas[:referencia]).to include("Descargas", "Excel", "PDF")
      end

      # El «sin pedido a la IA» de arriba no afirma nada: el desafío corre en
      # modo `human`, donde `shared/ai_actions` no dibuja botones para NADIE.
      # La guarda que se quiere probar es `pide_resumen`
      # (`policy(@challenge).update_pipeline?`), y sólo se ve con la IA
      # encendida. Un grupo aparte para no cambiarle el modo a los tres
      # ejemplos de arriba, que no hablan de IA.
      describe "con la IA asistida" do
        before { as_company(company) { challenge.update!(ai_default_mode: "ai_assisted") } }

        it "quien administra puede pedir el resumen narrativo" do
          sign_in(admin, company: company)
          get challenge_step_path(challenge, paso("reporting"))

          expect(response.body).to include("purpose=summarize_challenge")
        end

        it "quien evalúa no" do
          sign_in(elena, company: company)
          get challenge_step_path(challenge, paso("reporting"))

          expect(response.body).not_to include("purpose=summarize_challenge")
        end

        it "quien participa tampoco" do
          sign_in(paula, company: company)
          get challenge_step_path(challenge, paso("reporting"))

          expect(response.body).not_to include("purpose=summarize_challenge")
        end
      end
    end
  end

  describe "idear" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        seed_form!(c.steps.create!(kind: "ideation", position: 1))
        c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
        c
      end
    end

    before do
      as_company(company) { challenge.pipeline.start! }
      expect(paso("ideation")).to be_active
    end

    it "quien administra: el formulario leído a la derecha y el editor en los ajustes" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("ideation"))

      expect(zonas[:referencia]).to include("Progreso", "Formulario de postulación", "Cómo quedó configurado")
      expect(documento.at_css('.ajustes [data-island="form-editor"]')).not_to be_nil
      expect(documento.css(".panel").map { |n| n["class"] }).to eq([])
      expect(titulos_de_mas_en_la_referencia).to be_empty
    end

    it "quien participa: lee el formulario, sin editor ni ajustes" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("ideation"))

      expect(zonas[:referencia]).to include("Formulario de postulación")
      expect(documento.at_css(".ajustes")).to be_nil
      expect(response.body).not_to include('data-island="form-editor"')
    end

    describe "la lista de ideas postuladas" do
      let!(:pedro) { member("pedro@test.dev", :participant) }

      before do
        postular!(challenge, author: paula, titulo: "Sensores de peso")
        postular!(challenge, author: pedro, titulo: "Cámaras en la merma")
      end

      # Quien participa compite por el mismo corte que las demás: ve sólo las
      # ideas en las que participa (`IdeaPolicy::Scope`). Las otras pantallas
      # de módulo ya filtraban con `@ideas_visibles`; idear no.
      it "quien participa ve sólo la suya, y el contador cuenta lo que ve" do
        sign_in(paula, company: company)
        get challenge_step_path(challenge, paso("ideation"))

        lista = documento.css(".app-main .card").find { |c| c.text.include?("Ideas postuladas") }
        expect(lista.text).to include("Sensores de peso")
        expect(lista.text).not_to include("Cámaras en la merma")
        expect(lista.text).not_to include(pedro.name)
        expect(lista.at_css(".section-title").text).to include("(1)")
      end

      it "quien administra las ve todas" do
        sign_in(admin, company: company)
        get challenge_step_path(challenge, paso("ideation"))

        lista = documento.css(".app-main .card").find { |c| c.text.include?("Ideas postuladas") }
        expect(lista.text).to include("Sensores de peso", "Cámaras en la merma")
        expect(lista.at_css(".section-title").text).to include("(2)")
      end
    end
  end

  describe "la cara de configuración" do
    let!(:challenge) do
      as_company(company) do
        c = create(:challenge, name: "Merma", ai_default_mode: "human")
        c.steps.create!(kind: "ideation", position: 1)
        c.steps.create!(kind: "evolution", position: 2, name: "Ronda")
        c.steps.create!(kind: "evaluation", position: 3, name: "Técnica")
        c.steps.create!(kind: "selection", position: 4, name: "Corte")
        c.steps.create!(kind: "reporting", position: 5, name: "Informe")
        c
      end
    end

    it "no sirve ningún panel viejo en los cinco kinds" do
      sign_in(admin, company: company)

      %w[ideation evolution evaluation selection reporting].each do |kind|
        get challenge_step_path(challenge, paso(kind))
        expect(documento.css(".panel").map { |n| n["class"] }).to eq([]), "quedó un .panel en #{kind}"
      end
    end

    # Lo que estaba partido en tarjetas sueltas con una sola cosa adentro: el
    # título, la descripción y la acción de IA de un bloque van juntos.
    #
    # El aserto de TEXTO solo no alcanza para probar eso: `#text` de Nokogiri
    # baja por todos los descendientes, así que da lo mismo si la acción de IA
    # está en el `card-body` o en otra tarjeta anidada adentro —que es
    # exactamente la forma vieja—. Y `[PANEL]` de `make screens` tampoco lo
    # ve: marca una `card` SIN `card-body`, no una `card` dentro de otra. Lo
    # que prueba el reagrupamiento es que la tarjeta no tenga otra adentro.
    it "el título de los criterios y su acción de IA están en la misma tarjeta" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      tarjeta = documento.css(".card").find { |c| c.at_css(".section-title")&.text.to_s.include?("Los criterios") }
      expect(tarjeta).not_to be_nil
      expect(tarjeta.text).to include("Proponer criterios con IA")
      expect(tarjeta.css(".card, .panel")).to be_empty
    end

    # `steps/config_congelada` sirve en DOS zonas con niveles distintos: a la
    # derecha es una tarjeta de consulta (`h3`, como el resto de la columna) y
    # acá es el reemplazo de la tarjeta «El módulo» para quien no puede
    # configurar, o sea una tarjeta del centro como cualquier otra (`h2`). Por
    # eso el nivel es un local y no una constante del partial.
    it "el resumen de sólo lectura de la cara de configuración es una tarjeta del centro" do
      sign_in(paula, company: company)
      get challenge_step_path(challenge, paso("evaluation"))

      # La cara de configuración no tiene columna de referencia: lo que se
      # configura es el trabajo de esa pantalla, no algo que se consulte.
      expect(documento.at_css(".app-aside")).to be_nil

      titulo = documento.css(".section-title").find { |n| n.text.strip.start_with?("Cómo") }
      expect(titulo).not_to be_nil
      expect(titulo.text.strip).to eq("Cómo está configurado")
      expect(titulo.name).to eq("h2")
    end

    it "el título del formulario y su acción de IA están en la misma tarjeta" do
      sign_in(admin, company: company)
      get challenge_step_path(challenge, paso("ideation"))

      tarjeta = documento.css(".card").find { |c| c.at_css(".section-title")&.text.to_s.include?("Formulario de postulación") }
      expect(tarjeta).not_to be_nil
      expect(tarjeta.text).to include("Proponer campos con IA")
      expect(tarjeta.css(".card, .panel")).to be_empty
    end
  end
end
