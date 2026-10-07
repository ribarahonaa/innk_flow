# frozen_string_literal: true

# Una mesa. En modo individual también existe: es una mesa de una persona.
# Un mecanismo y un gancho, en vez de dos caminos en el código.
class WorkshopGroup < ApplicationRecord
  include TenantScoped

  belongs_to :workshop
  has_many :workshop_group_members, dependent: :destroy
  has_many :workshop_proposals, dependent: :destroy
  # `dependent: :destroy` crea un peligro que `AssignGroups` tiene que conocer:
  # su barrido de mesas vacías se llevaría el texto de la mesa. Ver la cláusula
  # de `seat!`.
  has_many :workshop_drafts, dependent: :destroy
  has_many :members, through: :workshop_group_members, source: :user

  validates :name, presence: true

  # Las ideas de `challenge` que esta mesa puede trabajar: las que creó o en
  # las que colabora ALGUNO de sus integrantes, y nada más. Es la unión sobre
  # la mesa, no lo que ve cada persona por separado: «traé tu idea y la
  # mejoramos entre todos».
  #
  # `alive` y no `challenge.ideas` pelado, por dos razones distintas. Una
  # `eliminated` o `withdrawn` no se trabaja: proponer sobre algo que no pasó
  # un corte es ofrecer un control que no lleva a ninguna parte, y la sala no
  # daba ni un indicio de que estaba muerta. Y un `draft` que un integrante
  # creó FUERA del taller y nunca postuló pasaba a ser legible —título y
  # payload completo de su versión vigente— por toda su mesa: antes lo veía
  # sólo él. La ronda de evolución trabaja lo postulado.
  def workable_ideas(challenge)
    # La mesa de llegada no trabaja: es la sala de espera hasta que alguien
    # reparte. Acá es donde más importa, porque esto es la UNIÓN sobre los
    # integrantes: con treinta recién llegados, cada uno vería y propondría
    # sobre las ideas de los otros veintinueve.
    return Idea.none if arrival?

    member_ids = workshop_group_members.select(:user_id)
    ideas = challenge.ideas.alive
    ideas.where(author_id: member_ids)
         .or(ideas.where(id: IdeaContributor.where(user_id: member_ids).select(:idea_id)))
  end
end
