# frozen_string_literal: true

require "rails_helper"

# A quien le sacaron la membresía con la sesión todavía abierta.
#
# La sesión guarda la empresa elegida y `TenantResolution` no vuelve a pedir la
# membresía, así que el tenant sigue puesto y `current_membership` queda en
# `nil`. Varios `Scope` preguntaban «¿es gestor?» para restringir y devolvían
# `scope.all` en cualquier otro caso — incluido no tener rol. Quien acababa de
# perder el acceso listaba todos los desafíos de la empresa, y un gestor
# removido veía MÁS que antes, porque dejaba de estar acotado a los suyos.
RSpec.describe "sin membresía en la empresa del tenant", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:ex_gestor) do
    without_tenant do
      u = create(:user, email: "ex@test.dev")
      create(:membership, :gestor, company: company, user: u)
      u
    end
  end

  let!(:desafio) { as_company(company) { create(:challenge, name: "Merma en bodega") } }

  let!(:set_inline) do
    as_company(company) do
      paso = desafio.steps.create!(kind: "evaluation", position: 1, name: "Técnica")
      set = CriteriaSet.create!(name: "Criterios de la merma", scope: "inline", owner_step_id: paso.id)
      paso.update!(criteria_set: set)
      set
    end
  end

  before do
    sign_in(ex_gestor, company: company)
    without_tenant { Membership.where(user_id: ex_gestor.id).destroy_all }
  end

  it "no lista los desafíos de la empresa" do
    get challenges_path

    expect(response.body).not_to include("Merma en bodega")
  end

  it "no lee los criterios de un desafío" do
    get criteria_set_path(set_inline)

    expect(response).to have_http_status(:not_found)
  end
end
