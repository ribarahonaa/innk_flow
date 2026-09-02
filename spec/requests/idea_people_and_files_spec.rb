# frozen_string_literal: true

require "rails_helper"

# Colaboradores y adjuntos.
#
# Las dos tablas existían desde el principio y hay criterios automáticos que
# las consultan, pero no había dónde cargar el dato: «participan al menos N
# personas» y «adjuntó un archivo» eran filtros que nadie podía pasar.
RSpec.describe "quiénes participan y qué adjuntan", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role = nil)
    without_tenant do
      u = create(:user, email: email)
      role ? create(:membership, role.to_sym, company: company, user: u) : create(:membership, company: company, user: u)
      u
    end
  end

  let!(:owner) { member("owner@test.dev", :owner) }
  let!(:autora) { member("autora@test.dev") }
  let!(:colega) { member("colega@test.dev") }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      step = c.steps.create!(kind: "ideation", position: 1, name: "Postulación")
      seed_form!(step)
      step.form_fields.create!(key: "costeo", label: "Costeo", field_type: "file", position: 3)
      c
    end
  end

  let!(:idea) do
    as_company(company) do
      i = create(:idea, challenge: challenge, author: autora)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: autora).call
      i
    end
  end

  def reloaded = as_company(company) { Idea.find(idea.id) }
  def upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/costeo.txt"), "text/plain")

  describe "colaboradores" do
    before { sign_in(autora, company: company) }

    it "el detalle los lista y ofrece sumar a alguien" do
      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("Participan", autora.name, "Sumar")
    end

    # Es el punto de todo esto: el check existía y no lo podía cumplir nadie.
    it "sumar a alguien hace pasar «participan al menos 2 personas» de falso a verdadero" do
      criterion = as_company(company) do
        set = CriteriaSet.create!(name: "Gates", scope: "library")
        set.criteria.create!(name: "En equipo", key: "equipo", weight: 1, source: "automatic",
                             scale_type: "boolean", source_config: { "check" => "contributors_count",
                                                                     "minimum" => 2 })
      end

      expect(as_company(company) { criterion.verify(reloaded).passed? }).to be(false)

      post challenge_idea_contributors_path(challenge, idea),
           params: { user_id: colega.id, role: "contributor" }

      expect(as_company(company) { criterion.verify(reloaded).passed? }).to be(true)
      expect(as_company(company) { reloaded.people_count }).to eq(2)
    end

    it "no deja sumar dos veces a la misma persona" do
      2.times do
        post challenge_idea_contributors_path(challenge, idea),
             params: { user_id: colega.id, role: "contributor" }
      end

      expect(as_company(company) { reloaded.idea_contributors.size }).to eq(1)
      expect(flash[:alert]).to be_present
    end

    it "ni a quien creó la idea: ya cuenta" do
      post challenge_idea_contributors_path(challenge, idea),
           params: { user_id: autora.id, role: "contributor" }

      expect(as_company(company) { reloaded.idea_contributors.to_a }).to be_empty
      expect(flash[:alert]).to include("ya es quien creó la idea")
    end

    it "y se puede sacar" do
      post challenge_idea_contributors_path(challenge, idea),
           params: { user_id: colega.id, role: "contributor" }
      contributor = as_company(company) { reloaded.idea_contributors.first }

      delete challenge_idea_contributor_path(challenge, idea, contributor)

      expect(as_company(company) { reloaded.idea_contributors.to_a }).to be_empty
    end

    # Un colaborador no es decorativo: hay criterios que cuentan personas, así
    # que sumarlo con la evaluación en curso movería el puntaje después.
    it "no con el desafío ya evaluando: eso movería el puntaje después del hecho" do
      as_company(company) do
        challenge.steps.create!(kind: "evaluation", position: 2)
        challenge.pipeline.start!
        idea.update!(submitted_at: Time.current, status: "active")
        challenge.pipeline.advance!
      end

      post challenge_idea_contributors_path(challenge, idea),
           params: { user_id: colega.id, role: "contributor" }

      expect(as_company(company) { reloaded.idea_contributors.to_a }).to be_empty
    end
  end

  describe "adjuntos" do
    before { sign_in(autora, company: company) }

    it "el formulario declara el campo de archivo" do
      get edit_challenge_idea_path(challenge, idea)

      expect(response.body).to include('type="file"', 'name="files[costeo]"')
      expect(response.body).to include('enctype="multipart/form-data"')
    end

    it "subirlo hace pasar «adjuntó un archivo» de falso a verdadero" do
      criterion = as_company(company) do
        set = CriteriaSet.create!(name: "Gates", scope: "library")
        set.criteria.create!(name: "Costeada", key: "costeada", weight: 1, source: "automatic",
                             scale_type: "boolean", source_config: { "check" => "has_attachment",
                                                                     "field_key" => "costeo" })
      end

      expect(as_company(company) { criterion.verify(reloaded).passed? }).to be(false)

      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores" }, files: { costeo: upload } }

      expect(as_company(company) { criterion.verify(reloaded).passed? }).to be(true)
    end

    # Sin esto, corregir una palabra en otro campo dejaría a la versión nueva
    # sin el archivo y el criterio pasaría a fallar.
    it "el adjunto se arrastra a la versión siguiente sin volver a subirlo" do
      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores" }, files: { costeo: upload } }

      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores por rack" } }

      as_company(company) do
        version = Idea.find(idea.id).current_version
        expect(version.number).to eq(3)
        expect(version.attachments.map(&:field_key)).to eq(%w[costeo])
        expect(version.attachments.first.file).to be_attached
      end
    end

    # El mismo archivo, no una copia: es el mismo blob.
    it "y reusa el blob en vez de duplicar el archivo" do
      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores" }, files: { costeo: upload } }
      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores por rack" } }

      as_company(company) do
        blobs = Idea.find(idea.id).versions.flat_map { |v| v.attachments.map { |a| a.file.blob.id } }
        expect(blobs.uniq.size).to eq(1)
      end
    end

    # Subir un archivo ES un cambio, aunque el texto quede igual.
    it "subir un archivo publica versión aunque el payload no cambie" do
      expect do
        patch challenge_idea_path(challenge, idea),
              params: { payload: { titulo: "Sensores" }, files: { costeo: upload } }
      end.to change { as_company(company) { Idea.find(idea.id).versions.size } }.by(1)
    end

    it "el detalle ofrece descargarlo" do
      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores" }, files: { costeo: upload } }

      get challenge_idea_path(challenge, idea)

      expect(response.body).to include("costeo.txt")
    end

    it "descarta un archivo cuya clave no es un campo del formulario" do
      patch challenge_idea_path(challenge, idea),
            params: { payload: { titulo: "Sensores" }, files: { inventado: upload } }

      as_company(company) do
        expect(Idea.find(idea.id).current_version.attachments.to_a).to be_empty
      end
    end
  end
end
