# frozen_string_literal: true

require "rails_helper"

# Una propuesta de la IA tiene que aparecer en el panel de la pantalla que la
# pidió. Parece obvio y estuvo roto en tres tareas a la vez.
#
# LA CAUSA: `ai_suggestions` guarda UN objetivo —el CHECK de Postgres deja
# exactamente uno— y de esa única columna se sacaban DOS respuestas distintas:
# sobre qué actúa la propuesta, y desde qué pantalla se pidió. Para casi todas
# coinciden. Para las que se piden desde la pantalla de un módulo SOBRE una
# idea no: el objetivo es la idea y la pantalla es el módulo, así que el panel
# del módulo —que filtra por `challenge_step_id`— no las mostraba nunca.
# Apretabas el botón, el marco se repintaba y no aparecía nada.
#
# POR QUÉ ESTA GUARDA: el defecto entró porque no rompía ningún test. Las tres
# tareas tenían cobertura de que la IA respondía, de quién podía pedirla y de
# quién podía aceptarla; ninguna miraba si lo propuesto se podía VER. Y es un
# defecto que se reintroduce solo: sumar una tarea que se pida desde la
# pantalla de un módulo sobre una idea y olvidarse de `revisa_en` la deja
# invisible, en silencio.
#
# LO QUE NO VE, y hay que decirlo: sólo mira los pedidos escritos en las vistas
# de `app/views/steps/`. Un pedido armado desde un helper, desde una isla Vue o
# desde una vista de otro directorio que igual renderice el panel del módulo se
# le escapa. Tampoco mira las pantallas sin panel —`step_tests/new` pide
# `test_idea` y no renderiza ninguno—: ahí la propuesta se ve en el popup de
# respuesta, que lo trae el layout.
RSpec.describe "una propuesta se revisa donde se pidió", type: :lint do
  # Las pantallas de módulo son las que sirve `StepsController#show`, y su panel
  # filtra por el módulo. Todo `purpose:` escrito acá abajo se pide desde una.
  VISTAS_DE_MODULO = Rails.root.glob("app/views/steps/**/*.haml").freeze

  # El propósito tal como lo escribe el `button_to`/`link_to` de la vista.
  def self.pedidos_desde_modulos
    VISTAS_DE_MODULO.flat_map { |f| f.read.scan(/purpose: "([a-z_]+)"/) }.flatten.uniq.sort
  end

  let(:pedidos) { self.class.pedidos_desde_modulos }

  # Qué objetivo declara la tarea. Con el contexto vacío los valores son `nil`,
  # pero la CLAVE —que es lo único que importa acá— es la misma.
  def objetivo_de(purpose)
    Flow::AI::Tasks::Base.for(purpose).target_attributes.keys.first
  end

  def aplica_al_pedirse?(purpose) = Flow::AI::Tasks::Base.aplica_al_pedirse?(purpose)

  # Las que necesitan declarar `revisa_en = :modulo`: se piden desde la pantalla
  # de un módulo, apuntan a la idea y quedan PENDIENTES. Una tarea que se aplica
  # al pedirse nunca llega al panel, así que no le hace falta.
  def necesitan_modulo
    pedidos.select { |p| objetivo_de(p) == :idea && !aplica_al_pedirse?(p) }.sort
  end

  # El escáner: si el glob o la expresión se rompen, mide CERO y todo lo demás
  # da verde sin haber comparado nada. Es el mismo motivo por el que `[RITMO]` y
  # `[RELLENO]` cuentan cuánto midieron.
  it "el escáner encuentra los pedidos de IA de las pantallas de módulo" do
    expect(pedidos).to include("test_idea", "decide_verdicts", "suggest_feedback", "generate_ideas")
    expect(pedidos.size).to be >= 7
  end

  it "toda tarea pedida desde un módulo sobre una idea se revisa en el módulo" do
    expect(necesitan_modulo).not_to be_empty, "el filtro quedó midiendo cero"
    expect(Flow::AI::Tasks::Base.purposes_revisados_en_el_modulo.sort).to eq(necesitan_modulo)
  end

  # La otra mitad, y va junta a propósito: una declaración que nadie necesita es
  # una propuesta que se muestra en un módulo que no la pidió. La igualdad de
  # arriba cubre las dos direcciones; esto nombra la que se olvida.
  it "y no hay ninguna declarada de más" do
    de_mas = Flow::AI::Tasks::Base.purposes_revisados_en_el_modulo.sort - necesitan_modulo
    expect(de_mas).to be_empty
  end

  # El paso desde el que se revisa tiene que existir: si `revisa_en` dice
  # `:modulo` y nada sabe cuál, el panel vuelve a quedar vacío y el redirect de
  # aceptar cae al objetivo.
  it "las tres declaran actuar sobre algo que trae el módulo en su run" do
    Flow::AI::Tasks::Base.purposes_revisados_en_el_modulo.each do |purpose|
      expect(pedidos).to include(purpose), "«#{purpose}» dice revisarse en el módulo y no se pide desde ninguno"
    end
  end
end
