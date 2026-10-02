# frozen_string_literal: true

require "rails_helper"

# Entrar al taller escaneando. Idempotente a propósito: un link se escanea dos
# veces con los dedos fríos, y la segunda no puede mover a nadie de mesa.
RSpec.describe Flow::Workshops::CheckIn do
  let!(:company) { without_tenant { create(:company) } }

  def member(email, role = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role, company: company, user: u)
      u
    end
  end

  let!(:paula) { member("paula@test.dev") }
  let!(:pedro) { member("pedro@test.dev") }

  def workshop(mode: "group", status: "open", registered: true)
    as_company(company) do
      create(:workshop, mode: mode, status: status,
                        attendance_mode: registered ? "registered" : "presumed")
    end
  end

  def call(taller, person)
    as_company(company) { described_class.new(taller, User.find(person.id)).call }
  end

  it "sienta en la mesa de llegada y marca presente" do
    taller = workshop
    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.attended).to be(true)
    grupo = as_company(company) { result.member.workshop_group }
    expect(grupo.arrival).to be(true)
    expect(grupo.name).to eq(described_class::ARRIVAL_NAME)
  end

  it "la mesa de llegada es la misma para todos" do
    taller = workshop
    call(taller, paula)
    call(taller, pedro)

    mesas = as_company(company) { taller.workshop_groups.reload.to_a }
    expect(mesas.size).to eq(1)
  end

  it "es idempotente: escanear dos veces no duplica el asiento" do
    taller = workshop
    primero = call(taller, paula)

    segundo = nil
    expect { segundo = call(taller, paula) }.not_to raise_error
    expect(segundo).to be_ok
    expect(segundo.member.attended).to be(true)
    expect(segundo.member.id).to eq(primero.member.id)
    asientos = as_company(company) do
      WorkshopGroupMember.joins(:workshop_group)
                         .where(workshop_groups: { workshop_id: taller.id }, user_id: paula.id).count
    end
    expect(asientos).to eq(1)
  end

  # Quien ya estaba convocado a la mesa 3 no termina en la llegada por escanear.
  it "a quien ya tiene mesa lo marca presente sin moverlo" do
    taller = workshop
    mesa = as_company(company) { create(:workshop_group, workshop: taller, name: "Mesa 3") }
    as_company(company) do
      WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: false)
    end

    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.workshop_group_id).to eq(mesa.id)
    expect(result.member.attended).to be(true)
  end

  # En modo individual una mesa ES una persona: `Convoke#own_group` ya la arma.
  it "en modo individual no usa mesa de llegada" do
    taller = workshop(mode: "individual")
    result = call(taller, paula)

    expect(result).to be_ok
    grupo = as_company(company) { result.member.workshop_group }
    expect(grupo.arrival).to be(false)
    # Contra el nombre REAL de la persona y no contra un literal: el literal
    # ataría el test a lo que la factory genera hoy.
    expect(grupo.name).to eq(without_tenant { User.find(paula.id).name })
  end

  it "rechaza un taller que no está abierto" do
    result = call(workshop(status: "draft"), paula)

    expect(result).not_to be_ok
    expect(result.errors.to_sentence).to match(/no está abierto/i)
  end

  it "rechaza un taller con la presencia presumida" do
    result = call(workshop(registered: false), paula)

    expect(result).not_to be_ok
    expect(result.errors.to_sentence).to match(/no toma asistencia/i)
  end

  # Dos escaneos en el mismo segundo. El índice UNIQUE parcial es lo que
  # `find_or_create_by!` no puede garantizar, y sin el rescate la segunda
  # persona —que está entrando— se come un 500.
  it "sobrevive a que otro escaneo cree la mesa de llegada en el medio" do
    taller = workshop
    # La otra llegada ya existe ANTES de llamar: `arrival_group!` corre su
    # alta en un savepoint, y una fila creada desde adentro del stub se
    # desharía con él, que no es lo que hace un escaneo ajeno (ese commitea
    # por su lado).
    as_company(company) { create(:workshop_group, :arrival, workshop: taller) }
    llamadas = 0
    allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
      .to receive(:find_or_create_by!).and_wrap_original do |original, *args, &blk|
        llamadas += 1
        raise ActiveRecord::RecordNotUnique, "index_workshop_groups_on_workshop_id_arrival" if llamadas == 1

        original.call(*args, &blk)
      end

    result = call(taller, paula)

    expect(result).to be_ok
    expect(as_company(company) { result.member.workshop_group.arrival }).to be(true)
  end

  # El doble toque en un teléfono: otro escaneo de la MISMA persona la sienta
  # entre el `seat_of` y el `Convoke`. Quien ya quedó adentro no puede leer un
  # error, así que el resultado tiene que ser ok con el asiento presente.
  it "si otro escaneo de la misma persona la sentó en el medio, es éxito" do
    taller = workshop
    mesa = as_company(company) { create(:workshop_group, workshop: taller, name: "Mesa 3") }
    primera = true
    allow_any_instance_of(Flow::Workshops::Convoke).to receive(:call).and_wrap_original do |original, *args|
      if primera
        primera = false
        as_company(company) do
          WorkshopGroupMember.create!(workshop_group: mesa, user_id: paula.id, attended: false)
        end
      end
      original.call(*args)
    end

    result = call(taller, paula)

    expect(result).to be_ok
    expect(result.member.attended).to be(true)
    expect(result.member.workshop_group_id).to eq(mesa.id)
  end
end
