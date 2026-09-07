# frozen_string_literal: true

module Flow
  # Las cuentas sembradas para probar la maqueta.
  #
  # Existen para que cualquiera pueda entrar y ver el producto desde cada rol
  # sin pedirle credenciales a nadie. Por eso la pantalla de login las lista:
  # tener nueve cuentas y no saber cuál es cuál es lo mismo que no tenerlas.
  #
  # Fuera de producción, obviamente. Con una base real esto sería un tablón con
  # las llaves puestas.
  module Demo
    PASSWORD = "Test1234"

    # El sufijo `.test` está reservado por RFC 2606: ninguna cuenta real puede
    # tenerlo, así que sirve para distinguir lo sembrado de lo que no.
    SUFIJO = ".test"

    module_function

    def available? = !Rails.env.production?

    # Quién es quién: correo, nombre y en qué empresa con qué rol. Sale de la
    # base y no de una lista escrita a mano, así no se desactualiza cuando el
    # seed cambia.
    def accounts
      return [] unless available?

      Flow::Tenant.bypass! do
        por_usuario = Membership.includes(:company).group_by(&:user_id)

        User.where("email LIKE ?", "%#{SUFIJO}").order(:email).map do |user|
          { email: user.email, name: user.name,
            roles: por_usuario.fetch(user.id, []).map do |m|
              { empresa: m.company.slug, nombre: m.company.name, rol: m.role }
            end }
        end
      end
    rescue ActiveRecord::StatementInvalid
      # Sin base migrada la pantalla de login tiene que seguir andando.
      []
    end
  end
end
