# frozen_string_literal: true

# `tenant_table` / `add_tenant_fk` disponibles en toda migración.
#
# El include va acá y no al final de lib/flow/migration_helpers.rb porque ese
# archivo lo autoloadea Zeitwerk: un side effect ahí solo correría cuando algo
# referencie la constante, y las migraciones nunca la nombran.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.include(Flow::MigrationHelpers)
end
