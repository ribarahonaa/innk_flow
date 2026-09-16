# frozen_string_literal: true

require "rails_helper"

# Cómo se cierra un comentario. Antes había un solo camino —publicar una
# versión— y eso cerraba TODOS los abiertos de la idea de una vez.
RSpec.describe "resolver feedback", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev", name: "Olga Owner")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end
  let!(:author) do
    without_tenant do
      u = create(:user, email: "autor@test.dev", name: "Ana Autora")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end
  let!(:ajeno) do
    without_tenant do
      u = create(:user, email: "otro@test.dev")
      create(:membership, company: company, user: u, role: "participant")
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evolution", position: 2, name: "Ronda de feedback")
      c
    end
  end
  let(:step) { as_company(company) { challenge.steps.find_by(kind: "evolution") } }

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: author, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores", "solucion" => "Poner sensores" },
                                         author: author).call
      i.update!(submitted_at: Time.current)
      Flow::Handlers::Base.for(challenge.steps.find_by(kind: "evolution")).activate!
      i
    end
  end

  def feedback!(body: "¿Y el costo?", kind: "question")
    as_company(company) do
      FeedbackItem.create!(challenge_step: step, idea: idea, idea_version_id: idea.current_version_id,
                           author: owner, kind: kind, body: body)
    end
  end

  describe "cerrarlo a mano, uno por uno" do
    it "«Tomado en cuenta» lo cierra con quién y con qué nota" do
      item = feedback!
      sign_in(author, company: company)

      post resolve_challenge_step_feedback_item_path(challenge, step, item),
           params: { resolution: "acknowledged", note: "Lo hablamos en la reunión" }

      as_company(company) do
        item.reload
        expect(item).not_to be_open
        expect(item.resolution).to eq("acknowledged")
        expect(item.resolution_label).to eq("Tomado en cuenta")
        expect(item.resolved_by_id).to eq(author.id)
        expect(item.resolution_note).to eq("Lo hablamos en la reunión")
        expect(item.addressed).to be(true), "`addressed` es proyección de `resolution`"
      end
    end

    it "«No aplica» también lo cierra, y queda dicho" do
      item = feedback!
      sign_in(owner, company: company)

      post resolve_challenge_step_feedback_item_path(challenge, step, item),
           params: { resolution: "dismissed", note: "Sistemas ya lo confirmó" }

      as_company(company) do
        expect(item.reload.resolution).to eq("dismissed")
        expect(item.resolution_label).to eq("No aplica")
      end
    end

    it "cierra SOLO el que se eligió" do
      # Es el punto: antes, cerrar uno cerraba los tres.
      uno = feedback!(body: "¿Y el costo?")
      feedback!(body: "Acotá el piloto", kind: "suggestion")
      feedback!(body: "Confirmá con Sistemas", kind: "issue")
      sign_in(author, company: company)

      post resolve_challenge_step_feedback_item_path(challenge, step, uno),
           params: { resolution: "acknowledged" }

      as_company(company) do
        expect(FeedbackItem.where(idea_id: idea.id).count(&:open?)).to eq(2)
      end
    end

    it "se puede reabrir si el cierre fue apresurado" do
      item = feedback!
      sign_in(author, company: company)
      post resolve_challenge_step_feedback_item_path(challenge, step, item), params: { resolution: "dismissed" }

      post reopen_challenge_step_feedback_item_path(challenge, step, item)

      as_company(company) do
        expect(item.reload).to be_open
        expect(item.addressed).to be(false)
        expect(item.resolved_by_id).to be_nil
      end
    end
  end

  describe "cerrarlo publicando una versión" do
    it "marca los abiertos como respondidos, con la versión que los responde" do
      item = feedback!
      sign_in(author, company: company)

      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores", solucion: "Poner sensores. Costo: 8 celdas." },
                      change_note: "Agregué el costo" }

      as_company(company) do
        item.reload
        expect(item.resolution).to eq("answered")
        expect(item.resolution_label).to eq("Respondido en una versión")
        expect(item.addressed_by_version.label).to eq("v2")
      end
    end

    it "no toca los que ya estaban cerrados a mano" do
      cerrado = feedback!(body: "No aplica esto")
      abierto = feedback!(body: "¿Y el costo?")
      sign_in(author, company: company)
      post resolve_challenge_step_feedback_item_path(challenge, step, cerrado),
           params: { resolution: "dismissed", note: "Ya resuelto aparte" }

      patch challenge_idea_path(challenge, idea), params: { payload: { titulo: "Otra cosa" } }

      as_company(company) do
        expect(cerrado.reload.resolution).to eq("dismissed")
        expect(cerrado.resolution_note).to eq("Ya resuelto aparte")
        expect(abierto.reload.resolution).to eq("answered")
      end
    end
  end

  describe "quién puede cerrarlo" do
    it "el autor de la idea sí" do
      item = feedback!
      sign_in(author, company: company)
      post resolve_challenge_step_feedback_item_path(challenge, step, item), params: { resolution: "acknowledged" }
      expect(as_company(company) { item.reload }).not_to be_open
    end

    it "quien administra el desafío sí" do
      item = feedback!
      sign_in(owner, company: company)
      post resolve_challenge_step_feedback_item_path(challenge, step, item), params: { resolution: "acknowledged" }
      expect(as_company(company) { item.reload }).not_to be_open
    end

    # 404 y no 403: quien participa no ve la idea de otra persona, y un 403
    # le confirmaría que existe —y que tiene comentarios—. Este spec aceptaba
    # 403, que era justamente el oráculo.
    it "un tercero NO: quien comenta no decide si quedó atendido" do
      item = feedback!
      sign_in(ajeno, company: company)
      post resolve_challenge_step_feedback_item_path(challenge, step, item), params: { resolution: "dismissed" }

      expect(response).to have_http_status(:not_found)
      expect(as_company(company) { item.reload }).to be_open
    end
  end

  # La ficha de la idea mostraba el feedback de SOLO LECTURA: su autora veía
  # que le pidieron algo y no tenía dónde decir que lo atendió. Las acciones
  # estaban, pero solo en la pantalla del módulo — la vista de quien acompaña,
  # no la de quien postuló.
  describe "la ficha de la idea, que es donde entra su autora" do
    before do
      feedback!
      sign_in(author, company: company)
    end

    it "ofrece las mismas salidas que el tablero" do
      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("Tomado en cuenta")
      expect(response.body).to include("No aplica")
    end

    it "y ofrece que la IA la reescriba con ese feedback" do
      # El módulo nace en «Solo personas», donde la IA no interviene: es la
      # regla del modo, no un olvido.
      as_company(company) { step.update!(ai_mode: "ai_assisted") }

      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("Reescribir la idea con el feedback")
    end

    it "y no la ofrece con el módulo en «Solo personas»" do
      get challenge_idea_path(challenge, idea)

      expect(response.body).not_to include("Reescribir la idea con el feedback")
    end

    # Quien colabora en la idea también la trabaja: la regla de visibilidad
    # dice «participa ⇒ la ve», y no poder tocarla la dejaba a medias.
    it "quien colabora también puede cerrarlos" do
      as_company(company) { IdeaContributor.create!(idea: idea, user: ajeno, role: "contributor") }
      sign_in(ajeno, company: company)

      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("Tomado en cuenta")
    end

    # Verlos sin ninguna acción y sin explicación no distingue entre «cerró la
    # ronda» y «no soy quien puede».
    it "y si la ronda cerró, lo dice en vez de no mostrar nada" do
      as_company(company) { step.update!(status: "completed", completed_at: Time.current) }

      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("ya cerró: los comentarios quedan como están")
      expect(response.body).not_to include("Tomado en cuenta")
    end

    # Y quien no participa de esa idea no llega a su ficha.
    it "a un tercero no le muestra nada: la ficha ajena no se abre" do
      sign_in(ajeno, company: company)

      get challenge_idea_path(challenge, idea)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "el tablero ofrece las salidas" do
    it "muestra cómo cerrar cada comentario y cómo responder editando" do
      feedback!
      sign_in(author, company: company)

      get challenge_step_path(challenge, step)

      expect(response.body).to include("Responder editando la idea")
      expect(response.body).to include("Tomado en cuenta")
      expect(response.body).to include("No aplica")
    end

    it "un comentario cerrado muestra cómo se cerró y deja reabrirlo" do
      item = feedback!
      as_company(company) { item.resolve!(resolution: "dismissed", user: owner, note: "Sistemas lo confirmó") }
      sign_in(author, company: company)

      get challenge_step_path(challenge, step)

      expect(response.body).to include("No aplica", "Sistemas lo confirmó", "Reabrir")
    end
  end

  # Un comentario pertenece a SU ronda de evolución. Con dos rondas, la ficha
  # los mostraba en una lista plana: el feedback viejo se leía como si fuera el
  # que hay que atender ahora.
  describe "con más de una ronda de evolución" do
    let!(:segunda) do
      as_company(company) do
        paso = challenge.steps.create!(kind: "evolution", position: 3, name: "Segunda ronda")
        step.update!(status: "completed", completed_at: Time.current)
        paso.handler.activate!
        paso.reload
      end
    end

    let!(:viejo) { feedback!(body: "Lo de la ronda anterior") }

    let!(:nuevo) do
      as_company(company) do
        FeedbackItem.create!(challenge_step: segunda, idea: idea,
                             idea_version_id: idea.reload.current_version_id,
                             author: owner, kind: "suggestion", body: "Lo de la ronda de ahora")
      end
    end

    before { sign_in(author, company: company) }

    it "cada ronda se muestra por separado, con su nombre" do
      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("Ronda de feedback", "Segunda ronda")
      expect(response.body).to include("Lo de la ronda anterior", "Lo de la ronda de ahora")
    end

    # La ronda cerrada se pliega: la historia no se esconde, pero plegada no se
    # confunde con lo que hay que atender ahora.
    it "la cerrada va plegada y la que está en curso, abierta" do
      get challenge_idea_path(challenge, idea)

      expect(response.body).to match(/<details[^>]*feedback-round--cerrada/)
      expect(response.body).to include("en curso")
    end

    # Solo la ronda abierta ofrece cerrar comentarios.
    it "solo se pueden atender los de la ronda en curso" do
      get challenge_idea_path(challenge, idea)

      expect(response.body.scan(%(class="feedback-resolve")).size).to eq(1)
    end

    # Arrastrar lo que quedó abierto en una ronda anterior mezcla dos
    # conversaciones distintas.
    it "la IA reescribe con el feedback de SU ronda, no con el de la anterior" do
      # Las lecturas de la tarea son del dominio: van dentro del tenant.
      snapshot, prompt = as_company(company) do
        tarea = Flow::AI::Tasks::EvolveIdea.new(challenge: challenge, step: segunda, idea: idea)
        [tarea.context_snapshot, tarea.messages.last[:content]]
      end

      expect(snapshot["feedback_ids"]).to eq([nuevo.id])
      expect(prompt).to include("Lo de la ronda de ahora")
      expect(prompt).not_to include("Lo de la ronda anterior")
    end
  end
end

