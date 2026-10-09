# frozen_string_literal: true

require "rails_helper"

# Quien administra entra a una mesa y la trabaja sin sentarse. El riesgo de la
# feature es que nueve textos digan «tu mesa» sobre contenido ajeno.
RSpec.describe "entrar a una mesa del taller", type: :request do
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

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      # Nombre distintivo: la factory numera «Mesa N» y una aserción sobre ése
      # podría pasar sola.
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      # Sin una idea en la mesa la lista no se dibuja con título (sale el vacío
      # «Ninguna idea en esta mesa»), y los ejemplos que miran «Las ideas de …»
      # medirían una ausencia.
      create(:idea, challenge: challenge, author: ana, status: "draft")
      { workshop: workshop, link: link, mesa: mesa, challenge: challenge }
    end
  end

  def visitar(mesa: nil)
    get workshop_sala_path(idear[:workshop], idear[:link], mesa: mesa&.id)
  end

  context "quien administra y no está sentado" do
    before { sign_in(admin, company: company) }

    it "sin el parámetro sigue viendo que no tiene mesa" do
      # El comportamiento de hoy no cambia: entrar sin nombrar una mesa es lo
      # que era.
      visitar

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sólo se crea un borrador desde una mesa")
      expect(response.body).not_to include("Mesa del fondo")
    end

    it "nombrando una mesa trabaja ESA mesa" do
      visitar(mesa: idear[:mesa])

      expect(response.body).to include("data-draft-url")
    end

    it "los títulos dicen el NOMBRE de la mesa y no «tu mesa»" do
      # Es el riesgo nº1 de la spec: nueve textos que mienten en cuanto la mesa
      # es ajena.
      visitar(mesa: idear[:mesa])

      expect(response.body).to include("Mesa del fondo")
      expect(response.body).not_to match(/ideas de tu mesa/i)
    end

    it "avisa que la mesa es ajena y que lo que escriba queda a su nombre" do
      visitar(mesa: idear[:mesa])

      expect(response.body).to include("sin estar sentado")
      expect(response.body).to include("queda a tu nombre")
    end

    it "nombrando la mesa de LLEGADA no dice «tu mesa»" do
      # La rama de la llegada hoy sólo la ve quien está sentado ahí. Quien
      # administra puede nombrarla, y el texto tiene que acompañar.
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: idear[:workshop]) }

      visitar(mesa: llegada)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/tu mesa todavía no se armó/i)
    end
  end

  context "quien participa" do
    before { sign_in(ana, company: company) }

    it "ve «tu mesa» en su propia mesa, sin aviso" do
      visitar

      expect(response.body).to match(/ideas de tu mesa/i)
      expect(response.body).not_to include("sin estar sentado")
    end

    it "nombrando OTRA mesa sigue viendo la suya, sin 403" do
      # El parámetro se IGNORA, no se rechaza: un 403 confirmaría que esa mesa
      # existe.
      otra = as_company(company) do
        create(:workshop_group, workshop: idear[:workshop], name: "Mesa de la ventana")
      end

      visitar(mesa: otra)

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/ideas de tu mesa/i)
      expect(response.body).not_to include("Mesa de la ventana")
    end
  end

  context "quien administra y está sentado" do
    it "con asiento propio, el parámetro NO lo pisa" do
      # El invariante del que depende todo: el asiento propio gana SIEMPRE, y de
      # eso depende que nada de lo que ya funciona cambie —el seed sienta al
      # admin a propósito, y `[DRAFT]` y `[GRABAR]` lo miden—.
      #
      # Tiene que ser alguien SENTADO que además pueda nombrar mesas: con un
      # `participant` este ejemplo pasa igual con el `||` invertido, porque
      # `named_group` le devuelve nil por permiso y cae al asiento de rebote.
      otra = as_company(company) do
        create(:workshop_group_member, workshop_group: idear[:mesa], user: admin)
        create(:workshop_group, workshop: idear[:workshop], name: "Mesa de la ventana")
      end
      sign_in(admin, company: company)

      visitar(mesa: otra)

      expect(response.body).to match(/ideas de tu mesa/i)
      expect(response.body).not_to include("sin estar sentado")
      expect(response.body).not_to include("Mesa de la ventana")
    end
  end
end
