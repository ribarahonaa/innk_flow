# frozen_string_literal: true

require "rails_helper"

# Qué entradas de la navegación global ve cada rol.
#
# Existe porque `.app-nav` vivía sólo en el layout y NINGÚN spec la nombraba:
# se podía abrir «Criterios» o «Miembros» a quien participa y la suite quedaba
# en verde. Se escribió antes de mudar la nav al riel, a propósito: una red
# estrenada ya movida no distingue el refactor de la regresión.
#
# Las aserciones van por TEXTO y `href`, no por clase: así el riel la hereda
# sin editarla.
RSpec.describe "navegación global", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(role, email)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, role, company: company, user: u)
      u
    end
  end

  # Un link se busca por su `href` Y su texto: sólo por texto, «IA» matchea
  # cualquier mención; sólo por href, un link escondido en otra parte de la
  # pantalla lo daría por presente.
  def nav_link?(texto, path)
    response.body.include?(%(href="#{path}")) &&
      response.body.match?(/<a[^>]+href="#{Regexp.escape(path)}"[^>]*>\s*#{Regexp.escape(texto)}\s*</)
  end

  context "quien participa" do
    before { sign_in member(:participant, "part@test.dev"), company: company }

    it "ve Desafíos y Talleres" do
      get root_path
      expect(nav_link?("Desafíos", challenges_path)).to be true
      expect(nav_link?("Talleres", workshops_path)).to be true
    end

    # El control positivo de arriba es lo que hace que esta negativa valga:
    # sin él, las tres aserciones pasarían con la nav entera borrada.
    it "no ve lo que administra la empresa" do
      get root_path
      expect(nav_link?("Criterios", criteria_sets_path)).to be false
      expect(nav_link?("Miembros", members_path)).to be false
      expect(nav_link?("IA", ai_runs_path)).to be false
    end
  end

  context "quien administra" do
    before { sign_in member(:admin, "admin@test.dev"), company: company }

    it "ve las cinco entradas" do
      get root_path
      expect(nav_link?("Desafíos", challenges_path)).to be true
      expect(nav_link?("Talleres", workshops_path)).to be true
      expect(nav_link?("Criterios", criteria_sets_path)).to be true
      expect(nav_link?("Miembros", members_path)).to be true
      expect(nav_link?("IA", ai_runs_path)).to be true
    end
  end

  context "el gestor" do
    before { sign_in member(:gestor, "gestor@test.dev"), company: company }

    # `manages_challenges?` es `admin?`, así que el gestor NO las ve. Se asevera
    # el valor literal y no `manages_challenges?`: un ejemplo que deriva su
    # expectativa del código que prueba pasa igual con los dos mal.
    it "no ve Criterios, Miembros ni IA" do
      get root_path
      expect(nav_link?("Criterios", criteria_sets_path)).to be false
      expect(nav_link?("Miembros", members_path)).to be false
      expect(nav_link?("IA", ai_runs_path)).to be false
    end

    # El control positivo: sin esto, las tres negativas de arriba pasarían con
    # la navegación entera borrada.
    it "sí ve Desafíos y Talleres" do
      get root_path
      expect(nav_link?("Desafíos", challenges_path)).to be true
      expect(nav_link?("Talleres", workshops_path)).to be true
    end
  end

  # Review Focus #3, la mitad que se puede probar sin navegador: sin empresa en
  # contexto no hay nav. La tarea 5 agrega la del riel.
  it "no dibuja la nav sin empresa elegida" do
    u = without_tenant do
      user = create(:user, email: "multi@test.dev")
      create(:membership, :participant, company: company, user: user)
      create(:membership, :participant, company: create(:company, slug: "otra"), user: user)
      user
    end
    sign_in u
    get select_company_path
    expect(nav_link?("Desafíos", challenges_path)).to be false
  end
end
