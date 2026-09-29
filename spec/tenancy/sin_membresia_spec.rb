# frozen_string_literal: true

require "rails_helper"

# A quien le sacaron la membresía con la sesión todavía abierta.
#
# La sesión guarda la empresa elegida y `TenantResolution` no vuelve a pedir la
# membresía, así que el tenant seguía puesto y `current_membership` quedaba en
# `nil`. Lo que lo frenaba era que cada `Scope` devolviera `none` —varios
# devolvían `scope.all` y le mostraban la empresa entera—, o sea que dependía de
# que ningún `Scope` futuro se olvidara.
#
# Ahora la puerta también se cierra: sin membresía en la empresa de la sesión no
# se navega. Los `Scope` siguen devolviendo `none` y siguen probados acá, uno
# por uno y sin pasar por un request: son la segunda capa, y una segunda capa
# que nadie puede ejercitar deja de estar probada.
RSpec.describe "sin membresía en la empresa del tenant", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:otra) { without_tenant { create(:company, slug: "otra") } }

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

  def sesion = without_tenant { Session.find_by!(user_id: ex_gestor.id) }

  before do
    sign_in(ex_gestor, company: company)
    without_tenant { Membership.where(user_id: ex_gestor.id, company_id: company.id).destroy_all }
  end

  describe "la puerta" do
    it "no lo deja seguir navegando con el tenant puesto" do
      get challenges_path

      expect(response).to redirect_to(select_company_path)
      expect(flash[:alert]).to include("Ya no tenés acceso")
    end

    # El estado inválido no se tolera: se resuelve. Con la empresa todavía
    # anotada en la sesión, el tenant volvía a montarse en cada request y lo
    # único que lo frenaba era el redirect.
    it "y le olvida la empresa, que es lo que lo dejaba adentro" do
      get challenges_path

      expect(sesion.company_id).to be_nil
    end

    # La sesión sigue viva: esto cierra una empresa, no la puerta de entrada.
    it "sin cerrarle la sesión" do
      get challenges_path

      expect(sesion).to be_present
      get select_company_path
      expect(response).to have_http_status(:ok)
    end
  end

  # El caso que decide la forma del arreglo: perder UNA membresía no puede
  # dejar afuera de las demás.
  describe "con otra membresía viva" do
    let!(:en_la_otra) do
      without_tenant { create(:membership, :admin, company: otra, user: ex_gestor) }
    end

    it "lo manda a elegir la que le queda, y desde ahí trabaja" do
      get challenges_path
      expect(response).to redirect_to(select_company_path)

      post choose_company_path, params: { company_id: otra.id }
      expect(response).to redirect_to(root_path)

      get challenges_path
      expect(response).to have_http_status(:ok)
    end

    it "y la pantalla le ofrece la empresa que le queda, no la que perdió" do
      get challenges_path
      follow_redirect!

      lista = response.body[%r{<ul class="company-list">.*?</ul>}m]
      expect(lista).to include(otra.name)
      expect(lista).not_to include(company.name)
    end
  end

  # Y el caso sin salida: que la pantalla lo diga en vez de ofrecer una lista
  # vacía bajo el título «Elegí una empresa».
  describe "sin ninguna membresía" do
    it "la pantalla dice que no hay a dónde entrar" do
      get select_company_path

      expect(response.body).to include("No tenés acceso a ninguna empresa")
      expect(response.body).not_to include("Elegí una empresa")
    end

    # Sin esto el único botón de esa pantalla rebota contra `require_company` y
    # vuelve a la misma pantalla: quedaba encerrado.
    it "y puede cerrar sesión desde ahí" do
      delete logout_path

      expect(response).to redirect_to(login_path)
      expect(without_tenant { Session.where(user_id: ex_gestor.id).count }).to be_zero
    end

    # El de arriba sale en el PRIMER request tras la revocación, cuando la
    # empresa todavía está anotada en la sesión: pega contra la rama de la
    # membresía. Éste sale con la empresa ya desanotada, que es la otra rama de
    # `require_company` —y el estado real del `salir()` de `make screens`, que
    # llega ahí después de que `/challenges` lo expulse—.
    it "y también con la empresa ya desanotada" do
      get challenges_path
      expect(sesion.company_id).to be_nil

      delete logout_path

      expect(response).to redirect_to(login_path)
      expect(without_tenant { Session.where(user_id: ex_gestor.id).count }).to be_zero
    end
  end

  # Anti-sobrecorrección: la puerta se cierra sólo para quien perdió la
  # membresía.
  describe "quien sí la tiene" do
    let!(:ana) do
      without_tenant do
        u = create(:user, email: "ana@test.dev")
        create(:membership, :admin, company: company, user: u)
        u
      end
    end

    it "sigue navegando igual" do
      sign_in(ana, company: company)

      get challenges_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Merma en bodega")
    end
  end

  # La segunda capa. Ya no se puede ejercitar por request —la puerta responde
  # antes— y sigue siendo la regla que protege a todo `Scope` que sobreescriba
  # `resolve`: sin membresía, `none`.
  describe "los Scope, sin membresía" do
    it "no listan los desafíos de la empresa" do
      as_company(company) do
        expect(ChallengePolicy::Scope.new(nil, Challenge).resolve).to be_empty
      end
    end

    it "ni los criterios de un desafío" do
      as_company(company) do
        expect(CriteriaSetPolicy::Scope.new(nil, CriteriaSet).resolve).to be_empty
      end
    end
  end
end
