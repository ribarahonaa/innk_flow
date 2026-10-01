# frozen_string_literal: true

# Entrar a un taller escaneando su QR. La ÚNICA ruta pública de la app.
#
# El tenant sale del TOKEN y no de la sesión, porque quien abre esto todavía no
# tiene ninguna: es la misma razón por la que `SessionsController` ya levanta el
# scoping —el tenant es lo que estas pantallas ESTABLECEN, no algo que reciben—.
#
# Saltea las tres puertas de `ApplicationController`. La autorización es el
# token: es de UN taller, sirve sólo con el taller abierto y el modo puesto, y se
# revoca rotándolo.
class WorkshopCheckinsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_company

  layout "auth"

  before_action :set_workshop

  # El GET NUNCA muta. El link viaja por cámara y por chat, y un prefetch del
  # navegador o de quien lo reenvía no puede sentar a nadie. Siempre renderiza;
  # el botón POSTea.
  def show; end

  def create
    # Entre el GET y el POST alguien pudo cerrar el taller o apagar el modo: se
    # explica sobre la misma pantalla y NO se crea ninguna cuenta.
    return render(:show) unless @workshop.checkin_open?

    user = signed_in? ? current_user : resolve_user
    return render(:show, status: :unprocessable_content) if user.nil?

    ensure_membership(user)
    sign_in!(user, company: @workshop.company) unless signed_in?

    result = Flow::Workshops::CheckIn.new(@workshop, user).call
    if result.ok?
      redirect_to workshop_path(@workshop), notice: "Listo: estás en el taller."
    else
      flash.now[:alert] = result.errors.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_workshop
    # `Workshop` es `TenantScoped`: sin el bypass esta consulta revienta con
    # `MissingTenant` antes de encontrar nada. La excepción está declarada en
    # `spec/lint/tenant_bypass_spec.rb` con su razón.
    @workshop = Flow::Tenant.bypass! { Workshop.find_by(checkin_token: params[:token]) }
    raise ActiveRecord::RecordNotFound if @workshop.nil?

    # Desde acá el request corre dentro de la empresa del taller: es lo que
    # `require_company` haría si hubiera sesión.
    Current.company = @workshop.company
  end

  # Un solo formulario para «ya tengo cuenta» y «no tengo», y sin oráculo: un
  # email que existe se autentica, uno nuevo se crea, y cuando falla el mensaje
  # es el MISMO del login. Así la pantalla no dice si el email estaba.
  def resolve_user
    # Normalizar a mano, igual que `SessionsController#create`. Lo que está en
    # juego: `User` NO tiene validación de unicidad —sólo presencia y formato—,
    # así que un email autocapitalizado por el teléfono no se encontraría y el
    # `create` chocaría contra el índice único de la base: 500 en la cara de
    # quien está entrando.
    #
    # Es una REDUNDANCIA y conviene saberlo: `User` declara
    # `normalizes :email`, y en Rails 7.1 eso normaliza también el valor de los
    # finders, así que el `find_by` de abajo encontraría la cuenta igual. Se
    # escribe de todos modos porque esta pantalla crea cuentas sin sesión y no
    # tiene por qué depender de una normalización declarada en el modelo; está
    # medido con una mutación de cada lado, y el ejemplo del spec se pone rojo
    # sólo cuando faltan las DOS.
    email = params[:email].to_s.strip.downcase
    existing = User.find_by(email: email)
    return authenticated(existing) if existing

    user = User.new(email: email, name: params[:name].to_s.strip, password: params[:password].to_s)
    unless user.save
      flash.now[:alert] = user.errors.full_messages.to_sentence
      return nil
    end

    Identity.create!(user: user, provider: Identity::PASSWORD, uid: user.email)
    user
  end

  def authenticated(user)
    return user if user.authenticate(params[:password].to_s)

    flash.now[:alert] = t("auth.invalid_credentials")
    nil
  end

  # El rol va SÓLO en el bloque de creación. Con `role: "participant"` en el
  # `where`, la membresía de quien ya es admin no se encuentra y el `create` va
  # contra el UNIQUE (user_id, company_id): quien lleva el taller se come un 500
  # por escanear su propio QR. Medido con la mutación, y el 500 llega antes de
  # bajarle el rol —lo frena el `validates :user_id, uniqueness:` del modelo, no
  # el índice—, así que un ejemplo que sólo mire el rol da verde igual: el del
  # spec exige también el redirect.
  def ensure_membership(user)
    Membership.find_or_create_by!(user_id: user.id) { |m| m.role = "participant" }
  end
end
