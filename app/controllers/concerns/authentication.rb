# frozen_string_literal: true

# Abrir sesión: la fila en `sessions` y la cookie firmada.
#
# Vive acá y no en cada controller que lo hace porque las tres banderas de la
# cookie —permanente, httponly, same_site— tienen que decidirse UNA vez. Dos
# políticas de cookie que el día que difieran una de las dos está mal es peor
# que el concern.
module Authentication
  extend ActiveSupport::Concern

  private

  def sign_in!(user, company:)
    record = user.sessions.create!(
      company: company,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255),
      last_seen_at: Time.current
    )
    cookies.signed.permanent[:session_token] = { value: record.token, httponly: true, same_site: :lax }
    record
  end
end
