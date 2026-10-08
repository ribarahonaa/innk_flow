# frozen_string_literal: true

require "rails_helper"

# El borrador vuelve al recargar, y se va cuando la mesa lo manda. Lo segundo no
# es prolijidad: si el formulario sigue prellenado con lo ya mandado, la mesa lo
# manda de nuevo, que es el defecto que la sala de la mesa existe para arreglar.
RSpec.describe "sala del taller: el borrador se prellena", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, :participant, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:beto) { member("beto@test.dev") }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group, field: field, challenge: challenge }
    end
  end

  let!(:evolucion) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      step = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      create(:workshop_group_member, workshop_group: group, user: ana)
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      version = Flow::Ideas::PublishVersion.new(
        idea, payload: { field.key => "lo publicado" }, author: ana
      ).call.version
      { workshop: workshop, link: link, group: group, field: field, idea: idea,
        version: version, challenge: challenge }
    end
  end

  describe "en idear" do
    it "sin borrador el formulario arranca vacío" do
      sign_in(ana, company: company)
      get workshop_sala_path(idear[:workshop], idear[:link])

      expect(response.body).to include('name="payload[')
      expect(response.body).not_to include("a medio escribir")
    end

    # Lo que B existe para resolver: la mesa escribió y alguien recargó.
    it "con borrador de la mesa, el formulario trae el texto — aunque lo haya escrito otra persona" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: beto,
                                payload: { idear[:field].key => "a medio escribir" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(idear[:workshop], idear[:link])

      expect(response.body).to include("a medio escribir")
    end

    it "al crear la idea el borrador se va" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: ana, payload: { idear[:field].key => "a medio escribir" })
      end
      sign_in(ana, company: company)
      post workshop_sala_ideas_path(idear[:workshop], idear[:link]),
           params: { payload: { idear[:field].key => "ya está" } }

      expect(as_company(company) { WorkshopDraft.count }).to eq(0)
    end

    # La invariante de la transacción: con el borrado afuera, un fallo de
    # publicación se llevaba el texto de la mesa.
    it "si la publicación falla, el borrador sigue ahí" do
      as_company(company) do
        create(:workshop_draft, workshop_group: idear[:group], workshop_challenge: idear[:link],
                                updated_by: ana, payload: { idear[:field].key => "a medio escribir" })
      end
      allow_any_instance_of(Flow::Ideas::PublishVersion).to receive(:call).and_return(
        Flow::Ideas::PublishVersion::Result.new(ok: false, version: nil, errors: [ "Título en blanco" ])
      )
      sign_in(ana, company: company)
      post workshop_sala_ideas_path(idear[:workshop], idear[:link]),
           params: { payload: { idear[:field].key => "ya está" } }

      expect(as_company(company) { WorkshopDraft.count }).to eq(1)
    end
  end

  describe "en evolución" do
    it "sin borrador el formulario trae el contenido de la versión vigente" do
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      # El atributo del campo y no la presencia del texto: «lo publicado» también
      # sale en el título de la idea y en la tarjeta «Contenido», así que
      # `include("lo publicado")` pasaba con el prellenado roto.
      expect(response.body).to include('value="lo publicado"')
    end

    # El borrador GANA sobre la versión: es el texto que la mesa escribió.
    it "con borrador, el borrador le gana a la versión vigente" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("lo de la mesa")
      # Sólo discrimina porque el fixture usa `field_type: "text"`: en un
      # `textarea` o `rich_text` el valor va como contenido del elemento y no
      # como atributo, y esta aserción pasaría siempre. Si cambiás el tipo del
      # fixture, cambiá también ésta.
      expect(response.body).not_to include('value="lo publicado"')
    end

    it "al mandar la propuesta el borrador se va" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      post workshop_sala_proposals_path(evolucion[:workshop], evolucion[:link]),
           params: { idea_id: evolucion[:idea].id,
                     payload: { evolucion[:field].key => "lo de la mesa" } }

      as_company(company) do
        expect(WorkshopDraft.count).to eq(0)
        expect(WorkshopProposal.count).to eq(1)
      end
    end

    # El borrador de la idea A no puede prellenar el formulario de la idea B.
    it "el borrador de otra idea no se mezcla" do
      otra = as_company(company) do
        i = create(:idea, challenge: evolucion[:challenge], author: ana, status: "active")
        v = Flow::Ideas::PublishVersion.new(
          i, payload: { evolucion[:field].key => "contenido de la otra" }, author: ana
        ).call.version
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: i,
                                based_on_version: v, updated_by: ana,
                                payload: { evolucion[:field].key => "borrador de la otra" })
        i
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).not_to include("borrador de la otra")
      expect(response.body).to include("lo publicado")
      expect(otra).to be_present
    end

    # La trampa que el handoff no tenía: la mesa teclea sobre v1, el autor acepta
    # otra propuesta y la idea pasa a v2, y alguien de la mesa recarga. Gana el
    # borrador, pero el aviso lo dice: en silencio, la mesa mandaría una
    # propuesta que revierte v2 sin saberlo.
    it "avisa cuando la versión vigente avanzó desde que la mesa guardó" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
        Flow::Ideas::PublishVersion.new(
          evolucion[:idea], payload: { evolucion[:field].key => "lo nuevo" },
          author: ana, title: "La mía"
        ).call
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      # Lo que hace útil al aviso: decir CUÁL de los dos se está viendo. Se pide
      # la frase entera: «v2» suelto también sale del chip del selector y de
      # «Versión vigente: v2», o sea que pasaría con el aviso borrado.
      expect(response.body).to include("lo que tecleó tu mesa sobre v1, pero la versión vigente ya es v2")
      # El copy dice «más arriba»: si la tarjeta «Contenido» se mudara abajo del
      # formulario, el aviso mandaría al lado equivocado y nada se pondría rojo.
      expect(response.body.index(">Contenido<")).to be < response.body.index("lo que tecleó tu mesa")
      # Y el formulario sigue trayendo el texto de la mesa.
      expect(response.body).to include("lo de la mesa")
    end

    # El atributo que el JS manda de vuelta tiene que decir contra qué se prellenó
    # ESTE formulario, y con borrador puesto eso es el sello del BORRADOR y no la
    # versión vigente: abajo el prellenado sale de `draft.payload`, que se tecleó
    # contra `draft.based_on_version_id`.
    #
    # Hoy no cambia ningún comportamiento —el servidor sella sólo al crear la
    # fila, así que con borrador ignora lo que llega—, y es exactamente por eso
    # que hace falta el ejemplo: sin él, volver el atributo a
    # `selected.current_version_id` deja `make spec` y `[DRAFT] 2` en verde, y
    # resellar deja de ser un no-op seguro para volverse una regresión silenciosa
    # —el aviso de base vieja se apagaría— para quien saque la condición creyendo
    # que el cliente ya manda la base correcta.
    #
    # Una sola aserción a propósito: un `not_to include` con la versión nueva no
    # podría fallar dado que la de arriba pasa (hay UN solo formulario, con UN
    # solo atributo), y ésa es la forma del comentario disfrazado de aserción que
    # esta rama lleva catorce veces cazado.
    it "con borrador, `data-draft-base` lleva el sello del borrador y no la versión vigente" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
        Flow::Ideas::PublishVersion.new(
          evolucion[:idea], payload: { evolucion[:field].key => "lo nuevo" },
          author: ana, title: "La mía"
        ).call
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include(%(data-draft-base="#{evolucion[:version].id}"))
    end

    # La otra mitad: una guarda que siempre dispara no discrimina.
    it "no avisa cuando la versión no se movió" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).not_to include("lo que tecleó tu mesa")
    end

    # Review Focus: una idea sin versión vigente deja `based_on_version_id` en
    # NULL. El aviso no aparece —no hay contra qué comparar— y nada revienta.
    # Sin este ejemplo, el día que alguien vuelva `based_on_version` NOT NULL, el
    # borrador de una idea sin versión falla al guardar.
    it "una idea sin versión vigente no avisa y no revienta" do
      sin_version = as_company(company) do
        i = create(:idea, challenge: evolucion[:challenge], author: ana, status: "active")
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: i,
                                based_on_version: nil, updated_by: ana,
                                payload: { evolucion[:field].key => "sobre nada" })
        i
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: sin_version.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sobre nada")
      expect(response.body).not_to include("lo que tecleó tu mesa")
    end

    it "el sello nombra a quien guardó último" do
      as_company(company) do
        create(:workshop_draft, workshop_group: evolucion[:group],
                                workshop_challenge: evolucion[:link], idea: evolucion[:idea],
                                based_on_version: evolucion[:version], updated_by: ana,
                                payload: { evolucion[:field].key => "lo de la mesa" })
      end
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      # El nombre solo aparece en otros lados (integrantes, autor): se asevera la
      # frase completa del sello.
      expect(response.body).to include("Guardado por #{ana.name}")
    end

    # Literales a propósito: son lo único que la mesa lee para saber si su trabajo
    # está a salvo. Si la clave del locale desaparece el acuse pasa a ser un
    # `translation missing` y la guarda de capturas no se entera, porque compara
    # el atributo contra lo que el JS copió de ese mismo atributo.
    it "el sello trae los textos de guardado y de fallo, literales" do
      sign_in(ana, company: company)
      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include('data-saved-text="Guardado ahora."')
      expect(response.body).to include(
        'data-failed-text="No se pudo guardar: copiá el texto antes de salir."'
      )
    end

    # El único que prueba la cadena COMPLETA. Los de arriba arman el borrador con la
    # factoría, así que le ponen `based_on_version` a mano y nunca ejecutan el código
    # que lo escribe: el endpoint sella SÓLO al crear la fila, y si eso se rompiera
    # —resellando en cada autoguardado— el aviso no podría dispararse nunca y los
    # cuatro ejemplos de arriba seguirían verdes.
    #
    # Este párrafo vivía arriba del ejemplo de los literales, que se intercaló
    # entre los dos: describía a éste y se leía como si hablara de aquél.
    it "de extremo a extremo: la mesa autoguarda, la versión avanza, la mesa autoguarda de nuevo y el aviso aparece" do
      sign_in(ana, company: company)
      patch workshop_sala_draft_path(evolucion[:workshop], evolucion[:link]),
            params: { idea_id: evolucion[:idea].id,
                      payload: { evolucion[:field].key => "lo de la mesa" } }
      expect(response).to have_http_status(:no_content)

      as_company(company) do
        Flow::Ideas::PublishVersion.new(
          evolucion[:idea], payload: { evolucion[:field].key => "lo nuevo" },
          author: ana, title: "La mía"
        ).call
      end

      # El segundo autoguardado NO vuelve a sellar: por eso el aviso sobrevive.
      patch workshop_sala_draft_path(evolucion[:workshop], evolucion[:link]),
            params: { idea_id: evolucion[:idea].id,
                      payload: { evolucion[:field].key => "lo de la mesa, con otra letra" } }
      expect(response).to have_http_status(:no_content)

      get workshop_sala_path(evolucion[:workshop], evolucion[:link], idea: evolucion[:idea].id)

      expect(response.body).to include("lo que tecleó tu mesa sobre v1, pero la versión vigente ya es v2")
      expect(response.body).to include("lo de la mesa, con otra letra")
    end
  end
end
