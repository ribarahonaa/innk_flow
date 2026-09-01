# frozen_string_literal: true

# Aislamiento por empresa, capa de aplicación.
#
# La inversión clave respecto de innk_r5: SIN tenant en contexto la query
# REVIENTA, no devuelve todo. En r5 el scoping era manual y olvidarse
# significaba servir en silencio los datos de todas las empresas — así
# aparecieron ~50 fugas en la suite de regresión. Acá el olvido es ruidoso.
#
# Esta es la capa ergonómica. La garantía real la dan las FKs compuestas en la
# base (ver Flow::MigrationHelpers): Postgres rechaza atar una fila de la
# empresa A a un padre de la empresa B, aunque el código lo intente.
module TenantScoped
  extend ActiveSupport::Concern

  class MissingTenant < StandardError; end
  class CrossTenant < StandardError; end

  included do
    belongs_to :company

    default_scope do
      if Flow::Tenant.bypassed?
        all
      elsif (company_id = Current.company_id)
        where(arel_table[:company_id].eq(company_id))
      else
        raise MissingTenant,
              "#{name}: query sin Current.company. Envolvé en Flow::Tenant.with(company), " \
              "o en Flow::Tenant.bypass! si es un job, un seed o una task."
      end
    end

    before_validation :assign_tenant_from_current, on: :create
    validates :company_id, presence: true
    validate :tenant_matches_current
    validate :associations_within_tenant
  end

  class_methods do
    # belongs_to hacia otros modelos tenant-scoped. Se calcula una vez.
    def tenant_reflections
      @tenant_reflections ||= reflect_on_all_associations(:belongs_to).reject(&:polymorphic?).select do |reflection|
        next false if reflection.name == :company

        reflection.klass.include?(TenantScoped)
      rescue NameError
        false
      end
    end
  end

  private

  def assign_tenant_from_current
    self.company_id ||= Current.company_id
  end

  # Impide escribir en otra empresa aun teniendo el objeto en memoria (un
  # `find` bajo bypass, por ejemplo).
  def tenant_matches_current
    return if Flow::Tenant.bypassed?
    return if Current.company_id.blank?
    return if company_id == Current.company_id

    errors.add(:company_id, "pertenece a otra empresa")
  end

  # Cada belongs_to a otro modelo tenant-scoped debe apuntar a la MISMA empresa.
  # Corre incluso bajo bypass!: es la red de los jobs y los seeds, que son
  # justamente el lugar donde el scoping automático no está.
  def associations_within_tenant
    self.class.tenant_reflections.each do |reflection|
      target_id = public_send(reflection.foreign_key)
      next if target_id.blank?

      target = association(reflection.name).target
      target ||= Flow::Tenant.bypass! do
        reflection.klass.select(:id, :company_id).find_by(id: target_id)
      end
      next if target.nil? || target.company_id == company_id

      errors.add(reflection.foreign_key,
                 "pertenece a otra empresa (#{reflection.klass.name} #{target_id})")
    end
  end
end
