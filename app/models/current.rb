# frozen_string_literal: true

# Contexto de request. Lo setea TenantResolution (web) o Flow::Tenant.with (jobs).
class Current < ActiveSupport::CurrentAttributes
  attribute :company, :user, :session, :request_id

  def self.company_id = company&.id
  def self.user_id = user&.id
end
