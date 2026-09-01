# frozen_string_literal: true

# Nota de un criterio dentro de una evaluación.
#
# `criterion_key` y `weight_used` van CONGELADOS: editar el criteria_set más
# tarde no puede reescribir puntajes históricos.
class AssessmentScore < ApplicationRecord
  include TenantScoped

  belongs_to :assessment
  belongs_to :criterion, optional: true

  validates :criterion_key, presence: true, uniqueness: { scope: :assessment_id }

  def answered? = normalized_value.present?
end
