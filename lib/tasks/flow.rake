# frozen_string_literal: true

namespace :flow do
  desc "Borra los desafíos y todo lo que cuelga de ellos. Deja empresas, usuarios y la biblioteca de criterios."
  task limpiar_desafios: :environment do
    Flow::Tenant.bypass! do
      antes = Challenge.count

      # Los sets INLINE cuelgan de un módulo: se van con su desafío. Los de la
      # biblioteca son de la empresa y sobreviven — son plantillas reusables.
      inline = CriteriaSet.where(scope: "inline")

      Notification.delete_all
      Challenge.find_each(&:destroy)
      inline.reload.find_each(&:destroy)

      puts "Borrados #{antes} desafíos."
      puts "Quedan: #{Company.count} empresas · #{User.count} usuarios · " \
           "#{CriteriaSet.count} sets de criterios (biblioteca)."
      puts "Para volver a tener el demo: make seed"
    end
  end
end
