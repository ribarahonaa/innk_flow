# frozen_string_literal: true

require "rails_helper"

# El reparto de permisos del gestor, entero y en un solo lugar.
#
# Existe porque abrir un permiso de más NO rompe ningún test: simplemente deja
# pasar. Por eso la tabla pregunta siempre por tres sujetos, y el que caza el
# error es el gestor NO asignado: para él toda puerta tiene que dar `false`.
RSpec.describe "qué administra el gestor" do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def usuario(rol, email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:admin) { usuario(:admin, "admin@test.dev") }
  let!(:asignada) { usuario(:gestor, "asignada@test.dev") }
  let!(:ajena) { usuario(:gestor, "ajena@test.dev") }

  def desafio_con(*rasgos)
    as_company(company) do
      c = create(:challenge, *rasgos)
      c.steps.create!(kind: "ideation", position: 1)
      c
    end
  end

  let!(:borrador) { desafio_con }
  let!(:corriendo) { desafio_con(:running) }

  before do
    as_company(company) do
      ChallengeGestor.create!(challenge: borrador, user: asignada)
      ChallengeGestor.create!(challenge: corriendo, user: asignada)
    end
  end

  # `close?` sólo tiene sentido sobre un desafío en curso; el resto se
  # pregunta sobre el borrador, que es donde casi todas están vivas.
  def desafio_de(puerta) = puerta == :close? ? corriendo : borrador

  def responde?(persona, clase, puerta)
    as_company(company) do
      membresia = Membership.find_by!(user_id: persona.id)
      desafio = desafio_de(puerta).reload
      objetivo = clase == ChallengeStepPolicy ? desafio.steps.first : desafio

      clase.new(membresia, objetivo).public_send(puerta)
    end
  end

  # Variable local y no constante: un `PUERTAS = …` adentro del bloque de
  # `describe` se define sobre Object y se filtra a toda la suite.
  puertas = {
    ChallengePolicy => %i[builder? start? close? update_pipeline? curate_pool?],
    ChallengeStepPolicy => %i[advance? skip? manage_form? manage_criteria?
                              manage_assignments? report?]
  }

  puertas.each do |clase, lista|
    lista.each do |puerta|
      describe "#{clase}##{puerta}" do
        # El control: sin esto, un `false` parejo para los tres haría pasar la
        # fila entera sin que nadie pueda nada.
        it "la abre quien administra la empresa" do
          expect(responde?(admin, clase, puerta)).to be(true)
        end

        it "la abre el gestor al que le asignaron el desafío" do
          expect(responde?(asignada, clase, puerta)).to be(true)
        end

        it "se la niega al gestor al que no se lo asignaron" do
          expect(responde?(ajena, clase, puerta)).to be(false)
        end
      end
    end
  end

  describe "sobre una idea, una evaluación y un comentario" do
    let!(:autora) { usuario(:participant, "autora@test.dev") }

    let!(:idea) do
      as_company(company) do
        i = create(:idea, challenge: borrador, author: autora)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" },
                                        author: autora).call
        i.update!(submitted_at: Time.current)
        i.reload
      end
    end

    def puede?(persona)
      as_company(company) do
        membresia = Membership.find_by!(user_id: persona.id)
        yield(membresia)
      end
    end

    # Editar una idea postulada SIN ronda de evolución abierta: era la ventana
    # que acotaba al gestor y ahora no lo acota.
    it "editar la idea: la abre quien administra" do
      expect(puede?(admin) { |m| IdeaPolicy.new(m, idea).update? }).to be(true)
    end

    it "editar la idea: la abre el gestor asignado, sin ronda abierta" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, idea).update? }).to be(true)
    end

    it "editar la idea: se la niega al gestor no asignado" do
      expect(puede?(ajena) { |m| IdeaPolicy.new(m, idea).update? }).to be(false)
    end

    # La exclusión que NO se toca: postular es del autor. `submit?` es
    # `update? && !acompana?`, así que sigue cerrado aunque `update?` se abra.
    it "postular por el autor: sigue cerrado para el gestor asignado" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, idea).submit? }).to be(false)
    end

    it "postular ideas propias: sigue cerrado para el gestor asignado" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, Idea.new(challenge: borrador)).create? })
        .to be(false)
    end

    it "borrar la idea: la abre quien administra" do
      expect(puede?(admin) { |m| IdeaPolicy.new(m, idea).destroy? }).to be(true)
    end

    it "borrar la idea: la abre el gestor asignado" do
      expect(puede?(asignada) { |m| IdeaPolicy.new(m, idea).destroy? }).to be(true)
    end

    it "borrar la idea: se la niega al gestor no asignado" do
      expect(puede?(ajena) { |m| IdeaPolicy.new(m, idea).destroy? }).to be(false)
    end

    describe "evaluar sin asignación" do
      let!(:evaluacion) do
        as_company(company) { borrador.steps.create!(kind: "evaluation", position: 2) }
      end

      def evalua?(persona, sobre: nil)
        puede?(persona) do |m|
          AssessmentPolicy.new(m, Assessment.new(challenge_step: evaluacion, idea: sobre)).create?
        end
      end

      it "la abre quien administra" do
        expect(evalua?(admin)).to be(true)
      end

      it "la abre el gestor asignado, sin estar asignado al módulo" do
        expect(evalua?(asignada)).to be(true)
      end

      it "se la niega al gestor no asignado" do
        expect(evalua?(ajena)).to be(false)
      end

      # El orden de `create?` no se toca: primero llegar al desafío, después el
      # conflicto de interés, y recién ahí el rol. Si `administra?` se pone
      # antes, quien administra vuelve a poder puntuarse a sí mismo.
      it "y nadie puntúa una idea de la que participa, ni quien administra" do
        propia = as_company(company) { create(:idea, challenge: borrador, author: admin) }
        expect(evalua?(admin, sobre: propia)).to be(false)
      end
    end

    it "cerrar un comentario: la abre el gestor asignado" do
      comentario = as_company(company) do
        FeedbackItem.new(idea: idea, challenge_step: borrador.steps.first)
      end
      expect(puede?(asignada) { |m| FeedbackItemPolicy.new(m, comentario).resolve? }).to be(true)
    end

    it "cerrar un comentario: se la niega al gestor no asignado" do
      comentario = as_company(company) do
        FeedbackItem.new(idea: idea, challenge_step: borrador.steps.first)
      end
      expect(puede?(ajena) { |m| FeedbackItemPolicy.new(m, comentario).resolve? }).to be(false)
    end

    # `administra?` recibe el desafío por cadenas opcionales
    # (`record.challenge_step&.challenge`), así que un `nil` tiene que dar
    # `false` y no reventar. Hoy nada lo fija: sacarle el `challenge.nil?` a
    # `reaches_challenge?` deja la tabla verde y revienta estas policies con
    # NoMethodError.
    it "un módulo sin desafío no abre nada, y no revienta" do
      expect(puede?(asignada) { |m| ChallengeStepPolicy.new(m, nil).advance? }).to be(false)
    end
  end

  describe "los criterios" do
    let!(:propio) do
      as_company(company) do
        modulo = borrador.steps.first
        CriteriaSet.create!(name: "Los del módulo", scope: "inline", owner_step: modulo)
      end
    end

    let!(:de_biblioteca) do
      as_company(company) { CriteriaSet.create!(name: "Compartidos", scope: "library") }
    end

    def guarda?(persona, set)
      as_company(company) do
        membresia = Membership.find_by!(user_id: persona.id)
        CriteriaSetPolicy.new(membresia, set.reload).update?
      end
    end

    it "el set propio del módulo: lo guarda quien administra" do
      expect(guarda?(admin, propio)).to be(true)
    end

    it "el set propio del módulo: lo guarda el gestor asignado" do
      expect(guarda?(asignada, propio)).to be(true)
    end

    it "el set propio del módulo: no el gestor no asignado" do
      expect(guarda?(ajena, propio)).to be(false)
    end

    # La biblioteca es de la empresa: se comparte con desafíos que el gestor
    # no ve, así que no la escribe ni el asignado.
    it "la biblioteca: la guarda quien administra" do
      expect(guarda?(admin, de_biblioteca)).to be(true)
    end

    it "la biblioteca: no la guarda el gestor asignado" do
      expect(guarda?(asignada, de_biblioteca)).to be(false)
    end

    it "ni la crea" do
      nuevo = as_company(company) { CriteriaSet.new(scope: "library") }
      creado = as_company(company) do
        membresia = Membership.find_by!(user_id: asignada.id)
        CriteriaSetPolicy.new(membresia, nuevo).create?
      end
      expect(creado).to be(false)
    end
  end
end
