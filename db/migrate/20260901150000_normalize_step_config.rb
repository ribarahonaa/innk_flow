# frozen_string_literal: true

# Un solo formato de configuración por módulo.
#
# Convivían dos formas de escribir lo mismo: el builder guardaba `cut_mode` y
# `cut_value` planos, `resolve_config!` guardaba `cut: {mode:, value:}`, y el
# handler leía las dos con un fallback. Cada lector nuevo tenía que acordarse
# de mirar en ambos lados.
#
# Se normaliza a la forma anidada, que es la que el motor ya usaba al congelar.
class NormalizeStepConfig < ActiveRecord::Migration[7.1]
  def up
    say_with_time "normalizando config de challenge_steps" do
      execute <<~SQL.squish
        UPDATE challenge_steps
        SET config = (config - 'cut_mode' - 'cut_value') ||
                     jsonb_build_object('cut', COALESCE(config -> 'cut', '{}'::jsonb) ||
                       jsonb_strip_nulls(jsonb_build_object(
                         'mode',  config -> 'cut_mode',
                         'value', config -> 'cut_value'
                       )))
        WHERE config ? 'cut_mode' OR config ? 'cut_value'
      SQL

      # `allow_partial` desaparece: hacía casi lo mismo que `require_response`
      # y entre los dos el resultado era difícil de predecir. Queda uno solo.
      execute <<~SQL.squish
        UPDATE challenge_steps
        SET config = (config - 'allow_partial') ||
                     jsonb_build_object('require_response',
                       to_jsonb(COALESCE((config ->> 'allow_partial')::boolean = false, false)))
        WHERE config ? 'allow_partial'
      SQL
    end
  end

  def down
    execute <<~SQL.squish
      UPDATE challenge_steps
      SET config = (config - 'cut') ||
                   jsonb_strip_nulls(jsonb_build_object(
                     'cut_mode',  config -> 'cut' -> 'mode',
                     'cut_value', config -> 'cut' -> 'value'
                   ))
      WHERE config ? 'cut'
    SQL
  end
end
