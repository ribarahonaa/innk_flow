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
end
