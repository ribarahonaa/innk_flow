# frozen_string_literal: true

require "rails_helper"

# De la mesa de llegada NO se trabaja, y son cuatro puertas porque cada sala
# tiene lectura y escritura.
#
# No es prolijidad: `WorkshopIdeasController` escribe `idea_contributors` para
# TODA la mesa, así que el primer borrador creado desde una llegada compartida
# nacería con sus treinta integrantes ESCRITOS, y repartir no los borra.
#
# Cada puerta tiene que tener un ejemplo que se ponga rojo al sacarla SOLA. Dos
# trampas lo impiden si no se mira: sin la guarda del controller de propuestas,
# `workable_ideas` ya es `none` y el `find_by!` da 404, que también «no crea
# nada»; y la sala ya pinta «todavía no se armó», así que el cuerpo tras el
# redirect no prueba que el rechazo lo dijo el controller. Por eso los POST
# miran el `flash[:alert]`, que sólo escribe `reject_arrival`.
RSpec.describe "la mesa de llegada no trabaja", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role.to_sym, company: company, user: u)
      u
    end
  end

  let!(:paula) { member("paula@test.dev", :participant) }

  # Un taller abierto con UN vínculo en `kind`, con Paula en la mesa de llegada.
  def taller_con_llegada(kind:)
    as_company(company) do
      taller = create(:workshop, :registered, status: "open")
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
      create(:form_field, challenge_step: step, key: "titulo", label: "Título") if kind == "ideation"
      link = create(:workshop_challenge, workshop: taller, challenge: challenge,
                                         challenge_step: step, status: "open")
      Flow::Workshops::CheckIn.new(taller, User.find(paula.id)).call
      [taller, link, challenge, step]
    end
  end

  describe "idear" do
    it "la sala no ofrece el formulario" do
      taller, link = taller_con_llegada(kind: "ideation")
      sign_in(paula, company: company)

      get workshop_sala_path(taller, link)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no se armó")
      expect(response.body).not_to include("Crear borrador")
    end

    it "el POST rechaza y no crea la idea" do
      taller, link = taller_con_llegada(kind: "ideation")
      sign_in(paula, company: company)

      expect {
        post workshop_sala_ideas_path(taller, link), params: { payload: { titulo: "Desde la llegada" } }
      }.not_to change { as_company(company) { Idea.count } }

      expect(response).to redirect_to(workshop_path(taller))
      # El aviso es del controller: la sala ya pinta la misma frase, así que el
      # cuerpo tras el redirect no distingue quién rechazó.
      expect(flash[:alert]).to include("todavía no se armó")
      # El taller con una sola sala redirige a ella: se pide la sala directo.
      get workshop_sala_path(taller, link)
      expect(response.body).to include("todavía no se armó")
    end
  end

  describe "evolución" do
    it "no lista ninguna idea de los otros integrantes" do
      taller, link, challenge, step = taller_con_llegada(kind: "evolution")
      otra = member("otra@test.dev", :participant)
      as_company(company) do
        Flow::Workshops::CheckIn.new(taller, User.find(otra.id)).call
        idea = create(:idea, challenge: challenge, author_id: otra.id, status: "active")
        # No hay factory de `StepEntry`: se crea con el modelo, igual que ya lo
        # hacen `assign_groups_spec.rb:27` y `workshop_mesas_spec.rb:130`.
        StepEntry.create!(challenge_step: step, idea: idea)
      end
      sign_in(paula, company: company)

      get workshop_sala_path(taller, link)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no se armó")
      expect(response.body).not_to include("Proponer")
    end

    it "el POST rechaza y no crea la propuesta" do
      taller, link, challenge = taller_con_llegada(kind: "evolution")
      idea = as_company(company) { create(:idea, challenge: challenge, author_id: paula.id, status: "active") }
      sign_in(paula, company: company)

      expect {
        post workshop_sala_proposals_path(taller, link),
             params: { idea_id: idea.id, payload: { titulo: "X" } }
      }.not_to change { as_company(company) { WorkshopProposal.count } }

      # Sin la guarda, `workable_ideas` ya es `none` y el `find_by!` da 404:
      # «no crea nada» también se cumple. Lo que distingue es el redirect con el
      # aviso propio del controller.
      expect(response).to redirect_to(workshop_path(taller))
      expect(flash[:alert]).to include("todavía no se armó")
    end
  end

  describe "#workable_ideas" do
    it "no devuelve nada desde la mesa de llegada" do
      taller, _link, challenge = taller_con_llegada(kind: "evolution")
      as_company(company) do
        create(:idea, challenge: challenge, author_id: paula.id, status: "active")
        llegada = taller.workshop_groups.find_by!(arrival: true)

        expect(llegada.workable_ideas(challenge)).to be_empty
      end
    end
  end
end
