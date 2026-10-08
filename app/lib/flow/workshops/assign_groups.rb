# frozen_string_literal: true

module Flow
  module Workshops
    # Arma las mesas del taller: elige la ENTRADA según la fase y delega el
    # reparto en `Seating`, que no toca la base.
    class AssignGroups
      Result = Data.define(:ok, :tables, :splits, :errors) do
        def ok? = ok
      end

      def initialize(workshop, size:)
        @workshop = workshop
        @size = size
      end

      def call
        # En borrador los vínculos no tienen módulo, así que no hay fase con la
        # que elegir el criterio.
        return failure("El taller tiene que estar abierto para armar las mesas.") unless @workshop.open?
        # El reparto por mesas no tiene sentido en modo individual: juntaría las
        # mesas de una persona, y una mesa reusada conservaría el nombre de quien
        # `Convoke#own_group` le puso.
        return failure("Un taller individual no se reparte en mesas.") if @workshop.individual?
        # Un taller abierto puede no tener fase: `MaterializeClosures` cierra los
        # vínculos vencidos de a uno y NO cierra el taller, así que «abierto con
        # todo cerrado» es un estado que la app produce sola. Sin fase no hay
        # criterio, y caer al `else` repartiría por cabeza a TODOS los
        # `participant` de la empresa, que nadie convocó.
        fase = @workshop.phase
        return failure("Los vínculos de este taller ya se cerraron: no hay fase sobre la que repartir.") if fase.nil?
        # Rearmar mueve gente entre mesas y borra las que queden vacías, y
        # `workshop_proposals.workshop_group_id` es ON DELETE CASCADE: una mesa
        # con propuestas se llevaría las aceptadas, que son la procedencia de
        # versiones ya publicadas. Con trabajo hecho, se mueve a mano.
        return failure("Ya hay propuestas en este taller: las mesas se mueven a mano.") if proposals?

        grupos = fase == "evolution" ? groups_by_idea : groups_by_person
        # `all?(&:empty?)` y no `empty?`: en evolución un hash con ideas pero
        # todas sin gente presente no es «hay a quién sentar». `Seating` las
        # descarta y devolveríamos cero mesas con ok? true.
        return failure("No hay a quién sentar.") if grupos.values.all?(&:empty?)

        seating = Seating.new(groups: grupos, size: @size).call
        @workshop.with_lock { seat!(seating.tables) }

        Result.new(ok: true, tables: seating.tables, splits: seating.splits, errors: [])
      end

      private

      def proposals?
        WorkshopProposal.joins(:workshop_group)
                        .where(workshop_groups: { workshop_id: @workshop.id })
                        .exists?
      end

      # Evolución: un grupo por idea del módulo, con su gente. Los `step_entries`
      # y no `challenge.ideas`, porque el módulo trabaja lo que entró en él.
      def groups_by_idea
        ideas = Idea.where(id: StepEntry.where(challenge_step_id: open_step_ids).select(:idea_id)).alive
        por_idea = ideas.to_h { |idea| [idea.id, people_of(idea)] }
        # La regla de no evictar: quien ya está sentado y presente entra, aunque
        # no trabaje en ninguna idea. Sólo quien NO está en ninguna: sumar un
        # grupo de una persona que YA está en una idea no cambia las mesas —el
        # racimo las une y `personas` deduplica— pero sí agrega una clave que el
        # reparto puede elegir para desprender, y ahí el aviso anunciaría un
        # corte que no movió a nadie.
        sueltos = seated_present_ids - por_idea.values.flatten
        por_idea.merge(sueltos.to_h { |id| [id, [id]] })
      end

      # Idear: un grupo por persona. No hay ideas de las que deducir nada.
      def groups_by_person
        # Con la presencia REGISTRADA el pool automático sobra y además miente:
        # `participant_ids` son todos los `participant` de la empresa, así que
        # sentaría a quien no vino y dejaría al escaneo sin efecto. Acá no hace
        # falta restar `absent_ids` — `seated_present_ids` ya sale de
        # `presentes`, y una persona tiene UN asiento por taller (UNIQUE), así
        # que no puede estar en las dos listas.
        ids = if @workshop.registered_attendance?
                seated_present_ids
              else
                (participant_ids | seated_present_ids) - absent_ids
              end
        ids.to_h { |id| [id, [id]] }
      end

      # Los ausentes salen del pool en las DOS fases. En evolución no es un
      # extra: si alguien no vino, su idea pierde a esa persona y eso CAMBIA los
      # racimos. Ignorarlo dejaría mesas armadas alrededor de gente que no está.
      #
      # Cómo se lee «no vino» depende del modo. Con la presencia PRESUMIDA se
      # descuenta sólo a quien está marcado ausente, porque a quien nunca se
      # convocó se lo presume presente. Con la presencia REGISTRADA no alcanza:
      # `absent_ids` sólo conoce a quien TIENE asiento, así que el autor que
      # nunca escaneó no aparecería ahí y el reparto armaría su mesa igual,
      # alrededor de alguien que no está en la sala.
      def people_of(idea)
        gente = [idea.author_id] + IdeaContributor.where(idea_id: idea.id).pluck(:user_id)
        return gente & seated_present_ids if @workshop.registered_attendance?

        gente - absent_ids
      end

      def absent_ids
        @absent_ids ||= WorkshopGroupMember.where(attended: false).joins(:workshop_group)
                                           .where(workshop_groups: { workshop_id: @workshop.id })
                                           .pluck(:user_id)
      end

      # `workable?` y no `open?`: tras un `advance!` el vínculo sigue `open` con
      # su módulo ya `completed` hasta que alguien carga la sala y corre
      # `MaterializeClosures`, que busca justo `open? && !workable?` para dar con
      # esos vínculos vencidos. Acá no se materializa, así que `open?` a secas
      # rearmaría las mesas alrededor de una ronda que ya terminó.
      def open_step_ids = @workshop.workshop_challenges.select(&:workable?).map(&:challenge_step_id).compact

      def participant_ids
        Membership.where(company_id: @workshop.company_id, role: "participant").pluck(:user_id)
      end

      # Memoizado: `people_of` lo pregunta una vez por idea.
      def seated_present_ids
        @seated_present_ids ||= WorkshopGroupMember.presentes.joins(:workshop_group)
                                                   .where(workshop_groups: { workshop_id: @workshop.id })
                                                   .pluck(:user_id)
      end

      # Sienta a cada mesa. Mueve a los presentes, crea las mesas que falten y
      # borra SÓLO las que quedan vacías —seguro porque el guarda de propuestas
      # ya corrió—. Un ausente conserva su asiento, así que su mesa no queda
      # vacía y no se borra. Por eso una mesa reusada puede quedar con MÁS gente
      # que `size`: la suya más un ausente que conservó el asiento. Es a
      # propósito: el tamaño habla de quien está presente.
      #
      # La segunda cláusula del barrido (`workshop_proposals.empty?`) es LA
      # CARRERA y no cinturón y tirantes: el guarda de propuestas corrió FUERA
      # del lock, contra un escritor (`WorkshopProposalsController#create`) que
      # no toma ninguno. Si una propuesta entra a mitad del reparto y deja a su
      # mesa vacía, borrarla se llevaría la propuesta por el CASCADE. Una mesa
      # que sobrevive sólo por eso es un sobrante inocuo; perder la propuesta no.
      #
      # El borrador se suma por lo mismo y con dos diferencias. Su escritor
      # (`WorkshopDraftsController#update`) tampoco toma lock y se dispara como
      # mucho una vez cada dos segundos MIENTRAS alguien teclea —es un debounce
      # y no un ciclo: quieta la mesa, no se dispara nunca—, lo que sube la
      # PROBABILIDAD de caer en la ventana (no su ancho). Y acá la cláusula no
      # tapa un hueco que otro chequeo cubre: es
      # el ÚNICO chequeo, porque el guarda de arriba no mira borradores.
      # Lo que NO se toca es el guarda de arriba: negarse a repartir porque
      # alguien tecleó una palabra bloquearía una operación común por texto sin
      # mandar. Ese guarda existe por la procedencia de versiones publicadas, y
      # un borrador no la tiene.
      #
      # **La grabación se suma por lo mismo, y acá no hace falta ninguna
      # carrera.** En idear el guarda de arriba no se interpone NUNCA —sólo mira
      # `WorkshopProposal`, que es un artefacto de evolución—, así que cambiar
      # el tamaño de mesa o marcar a alguien ausente y repartir de nuevo es una
      # operación común, los presentes caen en las filas 0..n-1 y las de más
      # quedan vacías. El barrido se las llevaba con sus grabaciones:
      # `WorkshopGroup` declara `has_many :workshop_recordings, dependent:
      # :destroy`, la FK es `ON DELETE CASCADE` y `has_one_attached :file`
      # PURGA el blob. Y el argumento para conservar el audio es más filoso que
      # el del texto: la spec lo dice así —«sin el audio una transcripción mala
      # es definitiva», porque re-transcribir con otros parámetros es
      # exactamente cómo se arregla una diarización colapsada—, o sea que lo
      # que el barrido destruía no se reconstruye de ninguna forma. El guarda de
      # arriba tampoco se extiende a grabaciones, por la misma asimetría del
      # borrador: negarse a repartir porque alguien grabó bloquearía una
      # operación común, y conservar la mesa es la respuesta correcta.
      def seat!(tables)
        # La mesa de llegada NO es reusable: es la primera creada, así que
        # `existentes[0]` la convertiría en «Mesa 1» conservando `arrival: true`
        # y su nombre, y su sala quedaría muda para siempre. El barrido de
        # vacías de abajo la borra cuando se queda sin nadie.
        existentes = @workshop.workshop_groups.where(arrival: false).order(:created_at).to_a

        tables.each_with_index do |user_ids, i|
          mesa = existentes[i] || @workshop.workshop_groups.create!(name: "Mesa #{i + 1}")
          WorkshopGroupMember.presentes.joins(:workshop_group)
                              .where(workshop_groups: { workshop_id: @workshop.id }, user_id: user_ids)
                              .destroy_all
          # `attended: true` EXPLÍCITO y no heredado del default de la columna:
          # lo que se siembra acá viene de `seated_present_ids`, o sea gente
          # presente. Heredarlo acertaba por casualidad, y el default puede
          # querer lo contrario según el modo del taller.
          user_ids.each { |id| WorkshopGroupMember.create!(workshop_group: mesa, user_id: id, attended: true) }
        end

        @workshop.workshop_groups.reload.each do |mesa|
          mesa.destroy! if mesa.workshop_group_members.empty? && mesa.workshop_proposals.empty? &&
            mesa.workshop_drafts.empty? && mesa.workshop_recordings.empty?
        end
      end

      def failure(message) = Result.new(ok: false, tables: [], splits: [], errors: [message])
    end
  end
end
