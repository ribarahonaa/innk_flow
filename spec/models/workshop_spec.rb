# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workshop do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def link(workshop, kind:, status: "open")
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
    create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step, status: status)
  end

  describe "#phase" do
    it "en borrador es nil: sus vínculos todavía no tienen módulo" do
      as_company(company) do
        workshop = create(:workshop, status: "draft")
        create(:workshop_challenge, workshop: workshop)

        expect(workshop.phase).to be_nil
      end
    end

    it "abierto es el kind de sus vínculos abiertos, y los cerrados no cuentan" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "evolution")
        link(workshop, kind: "evolution")
        link(workshop, kind: "ideation", status: "closed")

        expect(workshop.phase).to eq("evolution")
      end
    end

    it "un vínculo `open` cuyo módulo ya se completó no cuenta" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "ideation").challenge_step.update_columns(status: "completed")

        expect(workshop.reload.phase).to be_nil
      end
    end

    it "con vínculos vivos de fases distintas es nil: no adivina" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "ideation")
        link(workshop, kind: "evolution")

        expect(workshop.phase).to be_nil
      end
    end

    # Con un solo vínculo no hay orden de filas que valga: fija `select(&:open?)`.
    it "con todos los vínculos cerrados es nil" do
      as_company(company) do
        workshop = create(:workshop, status: "open")
        link(workshop, kind: "ideation", status: "closed")

        expect(workshop.phase).to be_nil
      end
    end
  end

  describe "el modo de asistencia" do
    it "nace presumido y con token" do
      taller = as_company(company) { create(:workshop) }

      expect(taller.attendance_mode).to eq("presumed")
      expect(taller).to be_presumed_attendance
      expect(taller.checkin_token).to be_present
    end

    it "rechaza un modo que no existe" do
      taller = as_company(company) { build(:workshop, attendance_mode: "qr") }

      expect(taller).not_to be_valid
      expect(taller.errors[:attendance_mode]).to be_present
    end

    # El token es UNA de las dos cosas que el link necesita; la otra es el modo.
    # Separarlas es lo que deja rotar el token sin devolver la asistencia a
    # presumida en medio de la sesión.
    it "rota el token sin tocar el modo" do
      taller = as_company(company) { create(:workshop, :registered) }
      anterior = taller.checkin_token

      taller.regenerate_checkin_token

      # Contra la fila releída: lo que importa es que el token nuevo se
      # PERSISTIÓ y que el modo en la base sigue siendo el mismo.
      taller.reload
      expect(taller.checkin_token).not_to eq(anterior)
      expect(taller).to be_registered_attendance
    end
  end

  describe "#checkin_state" do
    it "es :off con el modo presumido, aunque esté abierto" do
      taller = as_company(company) { create(:workshop, status: "open") }

      expect(taller.checkin_state).to eq(:off)
      expect(taller).not_to be_checkin_open
    end

    it "distingue borrador de cerrado, para poder decir cuál es" do
      borrador = as_company(company) { create(:workshop, :registered, status: "draft") }
      cerrado  = as_company(company) { create(:workshop, :registered, status: "closed") }

      expect(borrador.checkin_state).to eq(:draft)
      expect(cerrado.checkin_state).to eq(:closed)
    end

    it "es :open con el modo puesto y el taller abierto" do
      taller = as_company(company) { create(:workshop, :registered, status: "open") }

      expect(taller.checkin_state).to eq(:open)
      expect(taller).to be_checkin_open
    end
  end

  describe "la mesa de llegada" do
    # La unicidad la tiene que dar la BASE: dos escaneos en el mismo segundo
    # atraviesan cualquier `find_or_create_by`.
    it "es una sola por taller" do
      taller = as_company(company) { create(:workshop) }
      as_company(company) { create(:workshop_group, :arrival, workshop: taller) }

      expect {
        as_company(company) { create(:workshop_group, :arrival, workshop: taller, name: "Otra") }
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    # Lo que distingue el índice PARCIAL del total: en un taller conviven las
    # mesas normales con la de llegada. Sin el `where: "arrival"` el UNIQUE
    # sobre `workshop_id` dejaría una sola mesa por taller, o sea rompería el
    # reparto entero.
    it "convive con las mesas normales del mismo taller" do
      taller = as_company(company) { create(:workshop) }
      as_company(company) { create(:workshop_group, workshop: taller, name: "Mesa 1") }

      expect {
        as_company(company) { create(:workshop_group, :arrival, workshop: taller) }
      }.not_to raise_error
    end

    it "no impide una llegada en otro taller" do
      uno = as_company(company) { create(:workshop) }
      otro = as_company(company) { create(:workshop) }
      as_company(company) { create(:workshop_group, :arrival, workshop: uno) }

      expect {
        as_company(company) { create(:workshop_group, :arrival, workshop: otro) }
      }.not_to raise_error
    end
  end

  describe "#arrival_group!" do
    # La carrera: el `find_or_create_by!` no ve la llegada que otro pedido está
    # por crear y su INSERT choca con el UNIQUE parcial. Se provoca la
    # violación REAL de Postgres (el stub inserta una segunda llegada), porque
    # lo que se prueba es qué le pasa a la transacción de afuera: sin
    # savepoint queda envenenada y el rescate revienta con
    # `InFailedSqlTransaction`. `Workshop.transaction` explícito: la del
    # ejemplo no es joinable y daría un savepoint sola, tapando lo probado.
    it "se recupera de la carrera aun adentro de una transacción" do
      as_company(company) do
        workshop = create(:workshop)
        existing = create(:workshop_group, :arrival, workshop: workshop)
        allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
          .to receive(:find_or_create_by!) { |proxy| proxy.create!(arrival: true, name: "duplicada") }

        found = Workshop.transaction { workshop.arrival_group! }

        expect(found).to eq(existing)
      end
    end

    it "en modo individual es nil" do
      as_company(company) do
        expect(create(:workshop, mode: "individual").arrival_group!).to be_nil
      end
    end
  end
end
