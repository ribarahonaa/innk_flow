# frozen_string_literal: true

require "rails_helper"

# «Sobre qué mesa estoy actuando» es una pregunta distinta de «cuál es mi mesa»,
# y vive en un solo lugar. Gana la mesa NOMBRADA y el asiento propio es el
# fallback de la entrada sin parámetro: quien administra no participa de ninguna
# mesa, así que no hay asiento propio que proteger. El orden lo miden dos
# ejemplos de `spec/requests/entrar_a_una_mesa_spec.rb`; acá viven las dos piezas
# que el concern usa, `group_named` y `enter_any_group?`.
RSpec.describe "la mesa sobre la que se actúa" do
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

  # Un taller con dos desafíos y dos mesas. Ana se sienta en la primera.
  # Los nombres son distintivos a propósito: la factory numera «Mesa N», así
  # que aseverar sobre «Mesa 3» puede pasar solo por la secuencia.
  let!(:setup) do
    as_company(company) do
      uno = create(:challenge)
      otro = create(:challenge)
      paso_uno = create(:challenge_step, challenge: uno, kind: "ideation", status: "active")
      paso_otro = create(:challenge_step, challenge: otro, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link_uno = create(:workshop_challenge, workshop: workshop, challenge: uno,
                                             challenge_step: paso_uno)
      link_otro = create(:workshop_challenge, workshop: workshop, challenge: otro,
                                              challenge_step: paso_otro)
      mesa_de_ana = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      otra_mesa = create(:workshop_group, workshop: workshop, name: "Mesa de la ventana")
      create(:workshop_group_member, workshop_group: mesa_de_ana, user: ana)
      { workshop: workshop, link_uno: link_uno, link_otro: link_otro,
        mesa_de_ana: mesa_de_ana, otra_mesa: otra_mesa, uno: uno, otro: otro }
    end
  end

  describe "Workshop#group_named" do
    it "encuentra una mesa de ESTE taller" do
      as_company(company) do
        expect(setup[:workshop].group_named(setup[:otra_mesa].id)).to eq(setup[:otra_mesa])
      end
    end

    it "no encuentra una mesa de OTRO taller" do
      # La búsqueda cuelga de `workshop_groups`, que filtra por taller y —vía
      # `TenantScoped`— por empresa: dos exclusiones independientes.
      as_company(company) do
        ajena = create(:workshop_group, workshop: create(:workshop, status: "open"))

        expect(setup[:workshop].group_named(ajena.id)).to be_nil
      end
    end

    it "no revienta con lo que llega del query: la basura cae a nil" do
      as_company(company) do
        expect(setup[:workshop].group_named("no-es-un-uuid")).to be_nil
        expect(setup[:workshop].group_named(nil)).to be_nil
        expect(setup[:workshop].group_named([1, 2])).to be_nil
      end
    end

    it "un array con un id REAL resuelve: `find_by` arma un IN y no castea el array" do
      # Medido, y escrito acá para que nadie lea «un array castea a nil»:
      # `?mesa[]=<uuid>` llega como `["<uuid>"]`, no es `blank?`, y `find_by`
      # castea elemento por elemento. No es un problema —resuelve la misma mesa
      # que el parámetro plano, con el mismo filtro por taller y por empresa—,
      # pero es la rama que un array de basura no ejercita.
      as_company(company) do
        expect(setup[:workshop].group_named([setup[:otra_mesa].id])).to eq(setup[:otra_mesa])
      end
    end
  end

  describe "ChallengePolicy#enter_any_group?" do
    it "es true para quien administra la empresa" do
      as_company(company) do
        m = Membership.find_by(user: admin)

        expect(ChallengePolicy.new(m, setup[:uno]).enter_any_group?).to be(true)
      end
    end

    it "es false para quien participa" do
      as_company(company) do
        m = Membership.find_by(user: ana)

        expect(ChallengePolicy.new(m, setup[:uno]).enter_any_group?).to be(false)
      end
    end

    it "para un gestor es por DESAFÍO y no por taller" do
      # `administers_any?` le daría true por administrar ALGUNO del taller. Acá
      # no alcanza: el permiso tiene que ser del desafío de esta sala, porque la
      # sala ya le da 404 en el brief de un desafío que no le asignaron.
      #
      # No hay factory `:challenge_gestor`: los specs que ya existen usan
      # `ChallengeGestor.create!` directo.
      gestor = member("gestor@test.dev", :gestor)
      as_company(company) do
        ChallengeGestor.create!(challenge: setup[:uno], user: gestor)
        m = Membership.find_by(user: gestor)

        expect(ChallengePolicy.new(m, setup[:uno]).enter_any_group?).to be(true)
        expect(ChallengePolicy.new(m, setup[:otro]).enter_any_group?).to be(false)
      end
    end
  end
end
