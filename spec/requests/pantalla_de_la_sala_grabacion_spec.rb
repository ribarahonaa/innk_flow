# frozen_string_literal: true

require "rails_helper"

# El bloque de grabación en las DOS caras de la sala.
RSpec.describe "sala del taller: el bloque de grabación", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:ana) { without_tenant { u = create(:user); create(:membership, :participant, company: company, user: u); u } }
  let!(:beto) { without_tenant { u = create(:user); create(:membership, :participant, company: company, user: u); u } }

  def sala(kind: "ideation", arrival: false)
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop, arrival: arrival)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      # En evolución la mesa necesita una idea trabajable para que la cara
      # dibuje trabajo: su rama vacía reemplaza TODO —a diferencia de la de
      # idear, donde el formulario va abajo igual—, y con ella se iría también
      # el bloque de grabación. `workable_ideas` es la unión sobre los
      # integrantes y filtra con `Idea.alive`, así que tiene que ser de alguien
      # de la mesa y estar `active`.
      idea = (create(:idea, challenge: challenge, author: ana, status: "active") if kind == "evolution")
      { workshop: workshop, link: link, group: group, idea: idea }
    end
  end

  def visitar(s)
    get workshop_sala_path(s[:workshop], s[:link])
  end

  it "la cara de idear trae el control, con la URL que enciende el JS" do
    s = sala
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include("data-recording-url")
    expect(response.body).to include(workshop_sala_recordings_path(s[:workshop], s[:link]))
  end

  it "trae la onda con sus 40 barras, escondida hasta que haya micrófono" do
    # Las barras van en el MARKUP y no las crea el JS: así Tailwind ve las
    # clases y un morph que borre los `style` en línea se arregla en el frame
    # siguiente. `hidden` porque una onda plana sin grabar se lee como un
    # micrófono que no toma nada.
    s = sala
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body.scan('class="waveform__bar"').size).to eq(40)
    expect(response.body).to match(/<div[^>]*class="waveform"[^>]*hidden/)
  end

  it "la última grabación abre su transcripción sola, y la anterior no" do
    # Hacer clic para ver lo que acabás de grabar es un paso que no agrega nada.
    # `recent_first`, así que la primera del listado es la última grabada.
    s = sala
    as_company(company) do
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana,
                                          created_at: 2.minutes.ago)
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana,
                                          created_at: 1.minute.ago)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body.scan(/<details open/).size).to eq(1)
    expect(response.body.scan(/<details/).size).to eq(2)
  end

  it "desde la mesa de llegada NO trae el control" do
    # Uno más de los lugares que preguntan `arrival?` —cuáles son lo enumera
    # CLAUDE.md, sin número—. Ofrecerlo igual sería un control que rebota en el
    # 403 del POST.
    s = sala(arrival: true)
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).not_to include("data-recording-url")
  end

  it "lista las grabaciones de la mesa con su transcripción" do
    s = sala
    as_company(company) do
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include("Hablante 1")
    expect(response.body).to include("Primera.")
  end

  it "avisa cuando la diarización colapsó" do
    s = sala
    as_company(company) do
      create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                              workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include(I18n.t("flow.recordings.collapsed_diarization"))
  end

  it "dice que no se detectó habla cuando la transcripción quedó vacía" do
    s = sala
    as_company(company) do
      create(:workshop_recording, workshop_group: s[:group], workshop_challenge: s[:link],
                                  recorded_by: ana, status: "ready", utterances: [])
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include(I18n.t("flow.recordings.no_speech"))
  end

  it "dice de qué proveedor salió, para que un fixture no se lea como real" do
    # Las DOS columnas, no sólo el modelo. Hasta la revisión final este ejemplo
    # aseveraba `fixture-v1` —el MODELO— con el título hablando del proveedor, y
    # pasaba igual si `provider` se borraba de la tabla entera. «fixture-v1» no
    # dice de dónde salió; «fixture/fixture-v1» sí.
    s = sala
    as_company(company) do
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).to include("fixture/fixture-v1")
  end

  it "quien acompaña el desafío y está sentado también graba" do
    # `IdeaPolicy#create?` excluye al gestor por conflicto de interés —no firma
    # ideas propias—, y el bloque de grabación vivía DENTRO de esa rama: un
    # gestor sentado en una mesa de idear veía sólo el mensaje del conflicto, ni
    # grabador ni transcripción. Grabar no pregunta por ideas: el POST pide
    # `work?`, mesa y que no sea la de llegada, y la transcripción la lee la
    # mesa entera.
    #
    # Sentarlo a mano es el camino real: la convocatoria manual sienta a quien
    # su rol no pone en el pool automático, y `AssignGroups` nunca lo evicta.
    s = sala
    gestor = without_tenant { u = create(:user); create(:membership, :gestor, company: company, user: u); u }
    as_company(company) do
      create(:workshop_group_member, workshop_group: s[:group], user: gestor)
      create(:workshop_recording, :ready, workshop_group: s[:group],
                                          workshop_challenge: s[:link], recorded_by: ana)
    end
    sign_in(gestor, company: company)

    visitar(s)

    expect(response.body).to include("data-recording-url")
    expect(response.body).to include("Primera.")
  end

  context "la cara de evolución" do
    # El archivo se tituló «las DOS caras» desde el primer commit y el `kind:`
    # del helper quedó sin un solo uso: la cara de evolución no tenía testigo de
    # request, así que borrar su línea de render dejaba `make spec` en verde y
    # el único que se enteraba era `[GRABAR]`, al precio de un recorrido entero.
    it "también trae el control, con la URL que enciende el JS" do
      s = sala(kind: "evolution")
      sign_in(ana, company: company)

      visitar(s)

      expect(response.body).to include("data-recording-url")
      expect(response.body).to include(workshop_sala_recordings_path(s[:workshop], s[:link]))
    end

    it "el contenedor lleva la idea elegida, que es el contexto que guarda el POST" do
      # `idea_id` es «qué idea tenía la sala elegida al apretar grabar». Con una
      # sola idea trabajable la sala la preselecciona, así que el atributo sale
      # sin pasar el parámetro.
      s = sala(kind: "evolution")
      sign_in(ana, company: company)

      visitar(s)

      expect(response.body).to include(%(data-idea-id="#{s[:idea].id}"))
    end

    it "una mesa sin ninguna idea trabajable sigue viendo el control y lo que ya grabó" do
      # La rama vacía de evolución reemplaza el TRABAJO, no la conversación: la
      # mesa ya grabó y perder el acceso a eso es el defecto. `workable_ideas`
      # filtra con `Idea.alive`, así que basta que la idea esté eliminada.
      s = sala(kind: "evolution")
      as_company(company) do
        s[:idea].update!(status: "eliminated")
        create(:workshop_recording, :ready, workshop_group: s[:group],
                                            workshop_challenge: s[:link], recorded_by: ana)
      end
      sign_in(ana, company: company)

      visitar(s)

      expect(response.body).to include("Ninguna idea para trabajar")
      expect(response.body).to include("data-recording-url")
      expect(response.body).to include("Primera.")
    end

    it "en idear el contenedor no lleva ninguna idea: la fase la decide la sala" do
      s = sala
      sign_in(ana, company: company)

      visitar(s)

      expect(response.body).to include("data-recording-url")
      expect(response.body).not_to include("data-idea-id")
    end
  end

  it "no lista las grabaciones de OTRA mesa del mismo taller" do
    s = sala
    as_company(company) do
      otra = create(:workshop_group, workshop: s[:workshop])
      create(:workshop_recording, :ready, workshop_group: otra, workshop_challenge: s[:link],
                                          recorded_by: beto,
                                          utterances: [ { "speaker" => 0, "start" => 0.0, "end" => 1.0,
                                                          "transcript" => "SECRETO-DE-OTRA-MESA",
                                                          "confidence" => 0.9,
                                                          "speaker_confidence" => 0.9 } ])
    end
    sign_in(ana, company: company)

    visitar(s)

    expect(response.body).not_to include("SECRETO-DE-OTRA-MESA")
  end
end
