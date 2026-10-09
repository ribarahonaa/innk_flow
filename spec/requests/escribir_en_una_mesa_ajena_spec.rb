# frozen_string_literal: true

require "rails_helper"

# Cuatro caminos que resuelven la mesa por separado. Si uno queda con
# `group_of(current_user)` no falla: escribe en la mesa equivocada, en silencio.
# Por eso hay un bloque por endpoint y no un ejemplo del mecanismo.
#
# Cada bloque dice lo mismo con el payload y el rechazo de SU endpoint: quien
# administra escribe sobre la mesa que nombra, quien participa escribe en la
# suya aunque nombre otra, la llegada no se abre para nadie, y quien administra
# OTRO desafío del taller no gana nada con nombrar una mesa.
RSpec.describe "escribir sobre una mesa ajena", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana)   { member("ana@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }
  let!(:gestor) { member("gestor@test.dev", :gestor) }

  # Un segundo desafío en el MISMO taller, al que se asigna el gestor: administra
  # ese y no el de la sala que se prueba.
  def assign_gestor_to_another_challenge(workshop, kind)
    as_company(company) do
      otro = create(:challenge)
      step = create(:challenge_step, challenge: otro, kind: kind, status: "active")
      create(:workshop_challenge, workshop: workshop, challenge: otro, challenge_step: step)
      ChallengeGestor.create!(challenge: otro, user: gestor)
    end
  end

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      otra = create(:workshop_group, workshop: workshop, name: "Mesa de la ventana")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      { workshop: workshop, link: link, mesa: mesa, otra: otra, field: field }
    end
  end

  # Evolución: la idea de ana la trabaja la mesa de ana.
  let!(:evolucion) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      round = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: round)
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      otra = create(:workshop_group, workshop: workshop, name: "Mesa de la ventana")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      { workshop: workshop, link: link, mesa: mesa, otra: otra, field: field, idea: idea }
    end
  end

  def llegada_de(setup)
    as_company(company) { create(:workshop_group, :arrival, workshop: setup[:workshop]) }
  end

  describe "el borrador" do
    def patch_draft(setup, mesa:)
      patch workshop_sala_draft_path(setup[:workshop], setup[:link]),
            params: { mesa: mesa.id, payload: { setup[:field].key => "texto" } }
    end

    it "quien administra escribe sobre la mesa que nombra" do
      sign_in(admin, company: company)

      patch_draft(idear, mesa: idear[:mesa])

      expect(response).to have_http_status(:no_content)
      as_company(company) do
        draft = WorkshopDraft.last
        expect(draft.workshop_group).to eq(idear[:mesa])
        expect(draft.updated_by).to eq(admin)
      end
    end

    it "quien participa nombrando otra mesa escribe en LA SUYA" do
      sign_in(ana, company: company)

      patch_draft(idear, mesa: idear[:otra])

      expect(response).to have_http_status(:no_content)
      expect(as_company(company) { WorkshopDraft.last.workshop_group }).to eq(idear[:mesa])
    end

    it "desde la mesa de llegada nombrada por parámetro, no escribe" do
      sign_in(admin, company: company)

      patch_draft(idear, mesa: llegada_de(idear))

      expect(response).to have_http_status(:forbidden)
      expect(as_company(company) { WorkshopDraft.count }).to eq(0)
    end

    it "quien administra OTRO desafío del taller no gana una mesa nombrándola" do
      assign_gestor_to_another_challenge(idear[:workshop], "ideation")
      sign_in(gestor, company: company)

      patch_draft(idear, mesa: idear[:mesa])

      expect(response).to have_http_status(:forbidden)
      expect(as_company(company) { WorkshopDraft.count }).to eq(0)
    end
  end

  describe "la idea nueva (idear)" do
    def post_idea(setup, mesa:)
      post workshop_sala_ideas_path(setup[:workshop], setup[:link]),
           params: { mesa: mesa.id, payload: { setup[:field].key => "Una idea de la mesa" } }
    end

    it "quien administra crea la idea con la mesa que nombra como contribuyente" do
      sign_in(admin, company: company)

      expect { post_idea(idear, mesa: idear[:mesa]) }
        .to(change { as_company(company) { Idea.count } }.by(1))

      as_company(company) do
        idea = Idea.order(:created_at).last
        expect(idea.author).to eq(admin)
        expect(idea.idea_contributors.map(&:user)).to eq([ ana ])
      end
    end

    it "quien participa nombrando otra mesa crea la idea para LA SUYA" do
      sign_in(ana, company: company)
      beto = member("beto@test.dev")
      as_company(company) { create(:workshop_group_member, workshop_group: idear[:otra], user: beto) }

      post_idea(idear, mesa: idear[:otra])

      as_company(company) do
        idea = Idea.order(:created_at).last
        expect(idea.author).to eq(ana)
        expect(idea.idea_contributors.map(&:user)).not_to include(beto)
      end
    end

    it "desde la mesa de llegada nombrada por parámetro, no crea nada" do
      sign_in(admin, company: company)

      expect { post_idea(idear, mesa: llegada_de(idear)) }
        .not_to(change { as_company(company) { Idea.count } })

      expect(response).to redirect_to(workshop_sala_path(idear[:workshop], idear[:link]))
      expect(flash[:alert]).to include("todavía no se armó")
    end

    it "quien administra OTRO desafío del taller no crea nada nombrando una mesa" do
      assign_gestor_to_another_challenge(idear[:workshop], "ideation")
      sign_in(gestor, company: company)

      expect { post_idea(idear, mesa: idear[:mesa]) }
        .not_to(change { as_company(company) { Idea.count } })

      expect(flash[:alert]).to include("no estás en ninguna")
    end
  end

  describe "la propuesta (evolución)" do
    def post_proposal(setup, mesa:)
      post workshop_sala_proposals_path(setup[:workshop], setup[:link]),
           params: { mesa: mesa.id, idea_id: setup[:idea].id,
                     payload: { setup[:field].key => "Mejor así" } }
    end

    it "quien administra propone con la mesa que nombra" do
      sign_in(admin, company: company)

      expect { post_proposal(evolucion, mesa: evolucion[:mesa]) }
        .to(change { as_company(company) { WorkshopProposal.count } }.by(1))

      expect(as_company(company) { WorkshopProposal.last.workshop_group }).to eq(evolucion[:mesa])
    end

    it "quien participa nombrando otra mesa propone desde LA SUYA" do
      sign_in(ana, company: company)

      post_proposal(evolucion, mesa: evolucion[:otra])

      expect(as_company(company) { WorkshopProposal.last.workshop_group }).to eq(evolucion[:mesa])
    end

    it "desde la mesa de llegada nombrada por parámetro, no propone" do
      sign_in(admin, company: company)

      expect { post_proposal(evolucion, mesa: llegada_de(evolucion)) }
        .not_to(change { as_company(company) { WorkshopProposal.count } })

      expect(flash[:alert]).to include("todavía no se armó")
    end

    it "quien administra OTRO desafío del taller no propone nombrando una mesa" do
      assign_gestor_to_another_challenge(evolucion[:workshop], "evolution")
      sign_in(gestor, company: company)

      expect { post_proposal(evolucion, mesa: evolucion[:mesa]) }
        .not_to(change { as_company(company) { WorkshopProposal.count } })

      expect(flash[:alert]).to include("no estás en ninguna")
    end
  end

  describe "la grabación" do
    before { allow(Flow::Workshops::TranscribeRecordingJob).to receive(:perform_later) }

    def audio
      Rack::Test::UploadedFile.new(
        StringIO.new("bytes-de-audio-que-no-se-transcriben-en-el-spec"),
        "audio/webm", original_filename: "mesa.webm"
      )
    end

    def post_recording(setup, mesa:)
      post workshop_sala_recordings_path(setup[:workshop], setup[:link]),
           params: { mesa: mesa.id, file: audio }
    end

    it "quien administra graba sobre la mesa que nombra" do
      sign_in(admin, company: company)

      post_recording(idear, mesa: idear[:mesa])

      expect(response).to have_http_status(:created)
      as_company(company) do
        grabacion = WorkshopRecording.last
        expect(grabacion.workshop_group).to eq(idear[:mesa])
        expect(grabacion.recorded_by).to eq(admin)
      end
    end

    it "quien participa nombrando otra mesa graba en LA SUYA" do
      sign_in(ana, company: company)

      post_recording(idear, mesa: idear[:otra])

      expect(response).to have_http_status(:created)
      expect(as_company(company) { WorkshopRecording.last.workshop_group }).to eq(idear[:mesa])
    end

    it "desde la mesa de llegada nombrada por parámetro, no graba" do
      sign_in(admin, company: company)

      post_recording(idear, mesa: llegada_de(idear))

      expect(response).to have_http_status(:forbidden)
      expect(as_company(company) { WorkshopRecording.count }).to eq(0)
    end

    it "quien administra OTRO desafío del taller no graba nombrando una mesa" do
      assign_gestor_to_another_challenge(idear[:workshop], "ideation")
      sign_in(gestor, company: company)

      post_recording(idear, mesa: idear[:mesa])

      expect(response).to have_http_status(:forbidden)
      expect(as_company(company) { WorkshopRecording.count }).to eq(0)
    end

    # El permiso era por TALLER (`WorkshopPolicy#update?`, «administra ALGÚN
    # desafío») sobre el audio de UN desafío: el gestor del desafío A bajaba por
    # URL la conversación hecha en la sala del B.
    it "quien administra OTRO desafío del taller no baja el audio de esta sala: 404" do
      grabacion = as_company(company) do
        rec = idear[:mesa].workshop_recordings.create!(
          workshop_challenge: idear[:link], recorded_by: ana, status: "pending"
        )
        rec.file.attach(io: StringIO.new("audio"), filename: "mesa.webm", content_type: "audio/webm")
        rec
      end
      assign_gestor_to_another_challenge(idear[:workshop], "ideation")
      sign_in(gestor, company: company)

      get workshop_sala_recording_path(idear[:workshop], idear[:link], grabacion)

      expect(response).to have_http_status(:not_found)
    end

    it "quien administra ESTE desafío sí baja el audio de cualquier mesa" do
      grabacion = as_company(company) do
        rec = idear[:mesa].workshop_recordings.create!(
          workshop_challenge: idear[:link], recorded_by: ana, status: "pending"
        )
        rec.file.attach(io: StringIO.new("audio"), filename: "mesa.webm", content_type: "audio/webm")
        rec
      end
      sign_in(admin, company: company)

      get workshop_sala_recording_path(idear[:workshop], idear[:link], grabacion)

      expect(response).to have_http_status(:ok)
    end
  end
end
