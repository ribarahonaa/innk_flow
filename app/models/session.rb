# frozen_string_literal: true

# Sesión persistida. No es TenantScoped a propósito: se resuelve ANTES de
# saber en qué empresa está el usuario — es lo que la establece.
class Session < ApplicationRecord
  belongs_to :user
  belongs_to :company, optional: true

  has_secure_token :token

  def touch_seen!(request)
    update_columns(
      last_seen_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255)
    )
  end
end
