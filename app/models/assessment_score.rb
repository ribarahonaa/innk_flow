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

  # Lo que se muestra en la ficha. Un criterio de fórmula guarda el resultado
  # crudo —`1.1428571428571428571428571`— porque de ahí sale la normalización;
  # mostrarlo entero no le dice nada a nadie.
  def display_value
    return "—" if raw_value.blank?
    return raw_value unless numeric_value

    number = numeric_value.to_d
    number == number.truncate ? number.to_i.to_s : number.round(2).to_s
  end
end
