# frozen_string_literal: true

require "rails_helper"

# Los vectores de las ideas: quién los calcula, dónde viven y para qué sirven.
RSpec.describe "vectores de las ideas" do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:challenge) { create(:challenge, name: "Merma") }
  let!(:step) { seed_form!(challenge.steps.create!(kind: "ideation", position: 1)) }

  def idea_con(titulo, texto = "cuerpo")
    idea = create(:idea, challenge: challenge)
    Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => titulo, "problema" => texto }).call
    idea.reload
  end

  def embeber!(idea) = Flow::Ideas::EmbedVersion.call(idea.reload.current_version)

  describe Flow::Ideas::EmbedVersion do
    it "guarda el vector y con qué modelo se calculó" do
      idea = idea_con("Sensores en racks")

      expect(embeber!(idea)).to be(true)

      fila = IdeaVersion.where(id: idea.current_version_id).pick(:embedding, :embedding_model, :embedded_at)
      vector, modelo, cuando = fila

      expect(vector).to be_present
      # Entra en la columna: la dimensión del proveedor y la de la base son la
      # misma o Postgres lo rechaza.
      expect(vector.count(",") + 1).to eq(Flow::AI::EMBEDDING_DIMENSIONS)
      expect(modelo).to eq("fixture-v1")
      expect(cuando).to be_present
    end

    # El vector es un derivado, no contenido: no puede disparar callbacks ni
    # tocar `updated_at` de la versión, que es un dato de la publicación.
    it "no toca la versión como contenido" do
      idea = idea_con("Sensores")
      antes = idea.current_version.updated_at

      embeber!(idea)

      expect(idea.current_version.reload.updated_at).to eq(antes)
    end
  end

  # Publicar no puede quedar esperando a un servicio externo ni fallar con él.
  it "publicar una versión encola su vector, no lo calcula en el request" do
    idea = create(:idea, challenge: challenge)

    expect { Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una" }).call }
      .to have_enqueued_job(Flow::Ideas::EmbedVersionJob)

    expect(IdeaVersion.where(id: idea.reload.current_version_id).pick(:embedding)).to be_nil
  end

  describe "la búsqueda por vector en DetectDuplicates" do
    let(:tarea) { Flow::AI::Tasks::DetectDuplicates.new(challenge: challenge, step: step, idea: nueva) }
    let(:nueva) { idea_con("Sensores de peso en los racks críticos") }

    def candidatas = tarea.send(:candidates)

    # Hasta NEIGHBOURS se mandan todas: buscar entre diez no ahorra nada, y con
    # vectores sin semántica real podría dejar afuera justo la duplicada.
    it "con pocas ideas ni se usa" do
      3.times { |n| embeber!(idea_con("Idea #{n}")) }
      embeber!(nueva)

      expect(tarea.send(:shortlist_source)).to eq("recientes")
      expect(candidatas.size).to eq(3)
    end

    it "con muchas, Postgres acota y la gemela queda primera" do
      15.times { |n| embeber!(idea_con("Idea distinta número #{n}")) }
      gemela = idea_con("Sensores de peso en los racks críticos")
      embeber!(gemela)
      embeber!(nueva)

      expect(tarea.send(:shortlist_source)).to eq("pgvector")
      expect(candidatas.size).to eq(Flow::AI::Tasks::DetectDuplicates::NEIGHBOURS)
      expect(candidatas.first.id).to eq(gemela.id)
    end

    # Dos modelos distintos no producen vectores comparables: mezclarlos daría
    # vecinas al azar con toda la pinta de ser un resultado.
    it "no mezcla vectores de modelos distintos" do
      15.times { |n| embeber!(idea_con("Idea distinta número #{n}")) }
      gemela = idea_con("Sensores de peso en los racks críticos")
      embeber!(gemela)
      embeber!(nueva)

      IdeaVersion.where(id: gemela.current_version_id).update_all(embedding_model: "otro-modelo-v9")

      expect(candidatas.map(&:id)).not_to include(gemela.id)
    end

    # Sin vectores calculados no hay búsqueda posible: se cae a la lista
    # reciente en vez de devolver nada.
    it "sin vectores vuelve a la lista de siempre" do
      15.times { |n| idea_con("Idea #{n}") }

      expect(tarea.send(:shortlist_source)).to eq("recientes")
      expect(candidatas.size).to eq(15)
    end
  end
end
