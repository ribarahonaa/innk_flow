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

  desc "Calcula los vectores que falten. FORCE=1 rehace los de otro modelo."
  task embeddings: :environment do
    proveedor = Flow::AI.embeddings_provider
    modelo = proveedor.embedding_model
    puts "Proveedor: #{proveedor.name} · modelo: #{modelo}"

    hechas = 0
    saltadas = 0

    # El bypass envuelve SOLO la lectura de empresas. Envolviendo todo, el
    # `with` de adentro no acota nada y cada empresa recorre las versiones de
    # todas —el doble de trabajo y el tenant equivocado en contexto.
    companies = Flow::Tenant.bypass! { Company.all.to_a }

    companies.each do |company|
      Flow::Tenant.with(company) do
        IdeaVersion.find_each do |version|
          # Un vector de otro modelo no se compara con los nuevos: o se
          # rehace, o se deja y se avisa. Rehacer sin pedirlo puede costar
          # plata en un desafío grande.
          vigente = version.embedded_at.present? && version.embedding_model == modelo
          desactualizado = version.embedded_at.present? && version.embedding_model != modelo

          if vigente || (desactualizado && !ENV["FORCE"])
            saltadas += 1
            next
          end

          hechas += 1 if Flow::Ideas::EmbedVersion.call(version)
        end
      end
    end

    puts "Vectores calculados: #{hechas} · sin tocar: #{saltadas}"
    desactualizadas = Flow::Tenant.bypass! do
      IdeaVersion.unscoped.where.not(embedded_at: nil).where.not(embedding_model: modelo).count
    end
    puts "Con vector de otro modelo (corré con FORCE=1 para rehacerlos): #{desactualizadas}" if desactualizadas.positive?
  end
end
