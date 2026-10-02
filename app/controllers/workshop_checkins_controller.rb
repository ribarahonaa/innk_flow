# frozen_string_literal: true

# Entrar a un taller escaneando su QR. La ÚNICA ruta pública que escribe datos
# del dominio sin que nadie haya probado quién es (el login también se sirve sin
# sesión, pero parte de alguien que se autenticó con su clave).
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
    #
    # 200 a propósito, y por lo mismo que el 422 de dos líneas más abajo es 422:
    # ese dice «lo que mandaste no sirve», y acá no vino nada mal — cambió el
    # taller entre que la pantalla se sirvió y se envió. Lo que se renderiza es
    # esta misma pantalla en su estado nuevo, o sea la respuesta del GET, y con
    # el token en la mano decir por qué no se puede entrar no confirma nada que
    # no se supiera. El spec lo fija; no es un 422 al que le falte el status.
    return render(:show) unless @workshop.checkin_open?

    user = signed_in? ? current_user : resolve_user
    return render(:show, status: :unprocessable_content) if user.nil?

    # Las tres escrituras de identidad —la cuenta en `resolve_user`, la membresía
    # y la sesión— van ANTES del asiento, y NINGUNA comparte transacción con él:
    # si `CheckIn` fallara, quedaría alguien con cuenta, membresía de la empresa
    # y sesión abierta pero sin asiento. O sea adentro de la empresa y afuera del
    # taller, que es lo que hay que saber antes de mover algo de acá.
    #
    # Hoy ese fallo no llega: las dos guardas de `CheckIn` son las mismas dos que
    # `checkin_open?` ya preguntó, sobre el MISMO objeto en memoria —nadie lo
    # recarga en el medio—, y los dos fallos de `Convoke` que pueden llegar hasta
    # acá dicen «ya está en una mesa» —la carrera la sentó entre el `seat_of` y
    # el `save`—, que es justo lo que absorbe su segundo `seat_of`.
    ensure_membership(user)
    ensure_session(user)

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
    begin
      saved = user.save
    rescue ActiveRecord::RecordNotUnique
      # Dos toques del mismo pulgar. El `find_by` de arriba y este `save` no son
      # atómicos, y `User` NO valida unicidad —sólo presencia y formato—, así que
      # lo que frena al segundo es el índice `index_users_on_lower_email` y lo
      # que sale es esta excepción, no una validación. Nada lo tapa del lado del
      # navegador: el `data-disable-with` que le pone `submit_tag` al botón
      # necesita JS y el layout `auth` no carga ningún bundle, así que el doble
      # toque llega a la base de verdad — y es lo más común que le pasa a un QR,
      # que además es el camino PRIMARIO de esta pantalla.
      #
      # Se resuelve por el camino idempotente, la misma forma con la que
      # `Flow::Workshops::CheckIn` resuelve la carrera del asiento: la fila que
      # creó el otro request es de la misma persona, y la clave que acaba de
      # tipear autentica contra ella. Si fueran dos personas distintas con el
      # mismo email y claves distintas, la que pierde recibe el mensaje genérico
      # del login, que es exactamente lo correcto.
      return authenticated(User.find_by(email: email))
    end

    unless saved
      flash.now[:alert] = user.errors.full_messages.to_sentence
      return nil
    end

    Identity.create!(user: user, provider: Identity::PASSWORD, uid: user.email)
    user
  end

  # `user&.` y no `user.`, igual que `SessionsController#create`: el llamado de la
  # carrera de arriba vuelve de un `find_by` que en teoría puede dar nil, y un
  # `NoMethodError` en el camino público es peor que el mensaje genérico.
  def authenticated(user)
    return user if user&.authenticate(params[:password].to_s)

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

  # La sesión tiene que quedar en la empresa del TALLER. Sin sesión se abre una;
  # con una viva se la MUEVE, que no es lo mismo que volver a abrirla.
  #
  # Por qué la empresa del taller y no la que traía: el redirect va a
  # `workshops#show`, que busca con `policy_scope(Workshop)` —o sea dentro de la
  # empresa de la SESIÓN, porque `Current.company` se rearma en cada request
  # desde ahí—. Con la sesión en otra empresa el taller no se encuentra y sale un
  # 404; sin ninguna —lo que deja el login de quien tiene varias membresías y no
  # eligió— rebota al selector. En los dos casos el check-in ya escribió la
  # membresía, el asiento y la presencia: el escaneo funcionó y la pantalla decía
  # que no.
  #
  # Por qué no un `sign_in!` más: crea una fila NUEVA en `sessions` y reemplaza
  # la cookie, pero no toca la anterior — y lo único que autentica es el token,
  # así que la vieja queda viva. Escanear un QR no puede dejar una segunda sesión
  # válida de la misma persona.
  #
  # El request en curso no necesita nada más: `set_workshop` ya puso
  # `Current.company`, y `Current.session` es este mismo objeto.
  def ensure_session(user)
    return sign_in!(user, company: @workshop.company) unless signed_in?

    current_session.update!(company_id: @workshop.company_id)
  end
end
