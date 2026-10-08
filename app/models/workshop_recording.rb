# frozen_string_literal: true

# La conversación de una mesa, grabada y transcrita.
#
# El audio se CONSERVA, y no por prolijidad: re-transcribir con otros parámetros
# es exactamente cómo se arregla una diarización colapsada, y sin el audio una
# transcripción mala es definitiva. El precio está declarado en la spec: queda
# una grabación de voces guardada y nadie escribió una política de retención.
#
# Sin `WorkshopRecordingPolicy`, por el mismo motivo que `WorkshopDraft` no tiene
# una: lo que autoriza es la SALA, y una policy vacía heredaría
# `show? = membership.present?`, o sea «cualquiera de la empresa».
class WorkshopRecording < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending transcribing ready failed].freeze

  belongs_to :workshop_group
  belongs_to :workshop_challenge
  belongs_to :idea, optional: true
  belongs_to :recorded_by, class_name: "User"

  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validate :group_and_room_share_workshop
  validate :idea_matches_room

  scope :recent_first, -> { order(created_at: :desc) }

  # El texto para EL MODELO: es lo que C2 le va a pasar en el prompt. Se DERIVA
  # y no se guarda: una columna con el texto plano sería la segunda fuente que
  # el día que difiera miente.
  #
  # Los hablantes se numeran desde 1 porque Deepgram los numera desde 0, y
  # «Hablante 0» no se lee como una persona.
  #
  # **Y no pasa por I18n a propósito, aunque la pantalla diga lo mismo.** El
  # partial rotula cada utterance con `t("flow.recordings.speaker")` para una
  # PERSONA; esto arma la entrada de un modelo. Que hoy las dos digan «Hablante
  # N» es una coincidencia, no una duplicación: unificarlas ataría el prompt al
  # idioma de la interfaz, y el día que la app se traduzca el prompt cambiaría
  # de idioma sin que nadie lo decida. Si alguien viene a «DRYear» esto, es
  # esto.
  #
  # En C1 no lo consume ninguna pantalla —existe para C2— y por eso lo cubre su
  # propio ejemplo: sin él sería código que nadie ejercita.
  def transcript_text
    utterances.map { |u| "Hablante #{u['speaker'].to_i + 1}: #{u['transcript']}" }.join("\n")
  end

  def speakers = utterances.map { |u| u["speaker"] }.uniq

  # ¿La diarización colapsó?
  #
  # Condición ESTRUCTURAL y no un umbral: todas las utterances del mismo
  # hablante mientras en la mesa hay dos o más personas. No hay corte sobre
  # `speaker_confidence` a propósito — se midió 0,196–0,687 sobre audio
  # sintético y no hay línea base de voces reales, así que cualquier número
  # sería inventado, y un umbral inventado es la guarda que da permiso. El
  # número se MUESTRA en la pantalla; no se juzga acá.
  #
  # Cuentan sólo los PRESENTES: la voz de quien no vino no puede estar en la
  # grabación, y contarlo avisaría de una separación fallida sobre una
  # transcripción correcta.
  #
  # Sin utterances no hay hablantes, así que la condición es false por sí sola.
  def collapsed_diarization?
    speakers.size == 1 && workshop_group.workshop_group_members.presentes.count > 1
  end

  private

  # La mesa y la sala tienen que ser del mismo taller. Las FK compuestas sólo
  # atan a la misma EMPRESA, así que esto no lo cubre Postgres. Mismo par de
  # validaciones que `WorkshopDraft`.
  def group_and_room_share_workshop
    return if workshop_group.nil? || workshop_challenge.nil?
    return if workshop_group.workshop_id == workshop_challenge.workshop_id

    errors.add(:workshop_group, "no es de este taller")
  end

  def idea_matches_room
    return if idea.nil? || workshop_challenge.nil?
    return if idea.challenge_id == workshop_challenge.challenge_id

    errors.add(:idea, "no es de este desafío")
  end
end
