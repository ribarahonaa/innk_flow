# frozen_string_literal: true

# Identidad GLOBAL: el email es único en toda la instalación y una persona
# puede pertenecer a varias empresas vía Membership. Por eso User no es
# TenantScoped — el lookup de login ocurre antes de que exista Current.company.
class User < ApplicationRecord
  has_secure_password validations: false

  has_many :identities, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :companies, through: :memberships
  has_many :sessions, dependent: :destroy

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  def membership_in(company)
    Flow::Tenant.bypass! { memberships.find_by(company_id: company&.id) }
  end

  # "¿En cuántas empresas está esta persona?" es una pregunta intrínsecamente
  # cross-tenant: User es global y sus membresías cruzan empresas por
  # definición. Por eso el bypass acá es correcto y no un atajo — está
  # declarado en la allowlist de spec/lint/tenant_bypass_spec.rb.
  def companies_count
    @companies_count ||= Flow::Tenant.bypass! { memberships.count }
  end

  def multi_company? = companies_count > 1

  def all_memberships
    Flow::Tenant.bypass! { memberships.includes(:company).to_a }
  end
end
