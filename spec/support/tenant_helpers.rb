# frozen_string_literal: true

module TenantHelpers
  # Corre el bloque dentro de una empresa, como lo haría un request.
  def as_company(company, &block) = Flow::Tenant.with(company, &block)

  # Azúcar para crear datos de setup sin pelear con el scoping.
  def without_tenant(&block) = Flow::Tenant.bypass!(&block)

  # Inicia sesión en un request spec.
  #
  # Va por el formulario real en vez de escribir la cookie a mano: Rack::Test
  # no expone `cookies.signed`, y además así el spec ejercita el mismo camino
  # que un usuario (incluido el selector de empresa cuando hay varias).
  def sign_in(user, company: nil, password: "Test1234")
    post login_path, params: { email: user.email, password: password }

    if company && response.redirect_url.to_s.end_with?(select_company_path)
      post choose_company_path, params: { company_id: company.id }
    end

    response
  end
end
