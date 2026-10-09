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

  # La OTRA cara de la sala. Las dos están medidas por separado a propósito (en
  # `make screens`, `[DRAFT]` y `[GRABAR]` cuentan caras): cuatro de las frases
  # viven en `_evolution` y sin esto podrían volver a decir «tu mesa» sobre una
  # mesa ajena sin que nada se ponga rojo.
  #
  # La idea es `active` y no `draft`: la cara de evolución lista por
  # `workable_ideas`, que filtra con `Idea.alive` y no trae borradores.
  let!(:evolucion) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      round = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: round)
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa de evolución")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      vacia = create(:workshop_group, workshop: workshop, name: "Mesa sin ideas")
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      version = Flow::Ideas::PublishVersion.new(
        idea, payload: { field.key => "lo publicado" }, author: ana
      ).call.version
      { workshop: workshop, link: link, mesa: mesa, vacia: vacia, idea: idea,
        version: version, field: field }
    end
  end

  def visitar_evolucion(mesa: nil)
    get workshop_sala_path(evolucion[:workshop], evolucion[:link], mesa: mesa&.id)
  end

  def borrador_viejo
    as_company(company) do
      create(:workshop_draft, workshop_group: evolucion[:mesa], workshop_challenge: evolucion[:link],
                              idea: evolucion[:idea], based_on_version: evolucion[:version],
                              updated_by: ana, payload: { evolucion[:field].key => "lo de la mesa" })
      # La versión avanza DESPUÉS del borrador: es lo que lo vuelve viejo.
      Flow::Ideas::PublishVersion.new(
        evolucion[:idea], payload: { evolucion[:field].key => "lo nuevo" }, author: ana
      ).call
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

      # La positiva apunta al TÍTULO: el nombre ya sale en el aviso y en la
      # referencia aunque el título dijera «tu mesa».
      expect(response.body).to include("Las ideas de Mesa del fondo")
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

  context "la cara de evolución" do
    it "quien administra, nombrando la mesa: el título dice el NOMBRE" do
      sign_in(admin, company: company)

      visitar_evolucion(mesa: evolucion[:mesa])

      expect(response.body).to include("Las ideas de Mesa de evolución")
      expect(response.body).not_to match(/ideas de tu mesa/i)
      expect(response.body).to include("sin estar sentado")
    end

    it "la rama de vacío también dice el nombre" do
      sign_in(admin, company: company)

      visitar_evolucion(mesa: evolucion[:vacia])

      expect(response.body).to include("Ninguna persona de Mesa sin ideas tiene ideas postuladas")
      expect(response.body).not_to match(/persona de tu mesa/i)
    end

    it "la rama de LLEGADA dice el nombre y no «tu mesa»" do
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: evolucion[:workshop]) }
      sign_in(admin, company: company)

      visitar_evolucion(mesa: llegada)

      expect(response.body).to include("Mesa de llegada todavía no se armó")
      expect(response.body).not_to match(/tu mesa todavía no se armó/i)
    end

    it "el aviso de base vieja dice el nombre de la mesa ajena" do
      borrador_viejo
      sign_in(admin, company: company)

      visitar_evolucion(mesa: evolucion[:mesa])

      expect(response.body).to include("lo que tecleó Mesa de evolución sobre")
      expect(response.body).not_to match(/tecleó tu mesa/i)
    end

    it "quien participa en su propia mesa ve «tu mesa» y ningún aviso" do
      borrador_viejo
      sign_in(ana, company: company)

      visitar_evolucion

      expect(response.body).to match(/ideas de tu mesa/i)
      expect(response.body).to include("lo que tecleó tu mesa sobre")
      expect(response.body).not_to include("sin estar sentado")
    end
  end

  # La puerta de entrada: un «Entrar» por mesa y por vínculo trabajable. Se
  # asevera sobre el HREF servido (con su `mesa=<id>`) y no sobre el texto: el
  # bloque vive junto a un `form_with`, y es el HTML servido lo que muestra si el
  # link quedó donde debía.
  context "el «Entrar» de la lista de mesas" do
    def entrar_href(workshop, link, mesa)
      "#{workshop_sala_path(workshop, link)}?mesa=#{mesa.id}"
    end

    def pantalla_del_taller
      get workshop_path(idear[:workshop])
    end

    # Segundo vínculo trabajable en el MISMO taller (misma fase: idear).
    let!(:segundo) do
      as_company(company) do
        challenge = create(:challenge, name: "Desafío del segundo piso")
        step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
        link = create(:workshop_challenge, workshop: idear[:workshop], challenge: challenge,
                                           challenge_step: step)
        { link: link, challenge: challenge }
      end
    end

    it "con un solo vínculo trabajable hay un «Entrar» pelado por mesa" do
      as_company(company) { segundo[:link].destroy! }
      sign_in(admin, company: company)

      pantalla_del_taller

      expect(response.body).to include(%(href="#{entrar_href(idear[:workshop], idear[:link], idear[:mesa])}"))
      expect(response.body).not_to include("Entrar ·")
    end

    it "no aparece en la mesa de llegada" do
      llegada = as_company(company) { create(:workshop_group, :arrival, workshop: idear[:workshop]) }
      sign_in(admin, company: company)

      pantalla_del_taller

      expect(response.body).not_to include("mesa=#{llegada.id}")
    end

    it "con dos vínculos trabajables cada mesa tiene dos, rotulados con el desafío" do
      sign_in(admin, company: company)

      pantalla_del_taller

      [idear[:link], segundo[:link]].each do |link|
        expect(response.body).to include(%(href="#{entrar_href(idear[:workshop], link, idear[:mesa])}"))
      end
      expect(response.body).to include("Entrar · Desafío del segundo piso")
      expect(response.body).to include("Entrar · #{idear[:challenge].name}")
    end

    it "quien participa no ve ninguno" do
      sign_in(ana, company: company)

      pantalla_del_taller

      expect(response.body).not_to include("mesa=#{idear[:mesa].id}")
    end

    it "un gestor de UNO de los dos desafíos ve el «Entrar» de ese y no el del otro" do
      gestor = member("gestor@test.dev", :gestor)
      as_company(company) { ChallengeGestor.create!(challenge: segundo[:challenge], user: gestor) }
      sign_in(gestor, company: company)

      pantalla_del_taller

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{entrar_href(idear[:workshop], segundo[:link], idear[:mesa])}"))
      expect(response.body).not_to include(%(href="#{entrar_href(idear[:workshop], idear[:link], idear[:mesa])}"))
    end
  end
end
