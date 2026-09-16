# frozen_string_literal: true

require "rails_helper"

# Ningún controller toca una idea por fuera de `policy_scope`.
#
# Quien participa ve sólo las ideas en las que participa, y lo que no ve da
# 404, no 403: un 403 confirma que la idea existe. Buscarla con
# `@challenge.ideas.find` y autorizar DESPUÉS rompe eso sin que nada lo
# muestre —la idea ajena rebota igual, sólo que con el código equivocado—.
# Pasó en cuatro de los seis lugares que buscaban una idea, y en cada uno
# alguien había escrito el `authorize`: el defecto no es olvidarse de
# autorizar, es el orden.
#
# La primera versión listaba las formas PROHIBIDAS (`ideas.find`,
# `Idea.find_by`) y la revisión la evadió de cinco maneras sin esfuerzo:
# `Idea.where(...).find`, `find_by_id`, `where(id:).first!`, una cadena
# partida en varias líneas, y cualquier línea con `policy_scope(` en alguna
# parte. Ésta está al revés: marca TODO uso de `Idea` o `.ideas` en un
# controller que no esté adentro de un `policy_scope(...)`, y lo que no busca
# nada va en una lista con su razón.
#
# La revisión de esa versión la evadió otra vez, de más formas. Tres eran
# errores honestos y están cerradas: una excepción eximía la LÍNEA entera
# (`when Idea then Idea.find(id)` pasaba), borrar los textos borraba también
# lo interpolado adentro (`"#{@challenge.ideas.find(x).title}"` pasaba), y una
# cadena con el punto al final de la línea dejaba `ideas.find` sin marcar.
#
# Lo que todavía no ve, dicho para que nadie le crea de más:
#
#   · Sólo mira `app/controllers`. Un helper o un presenter que busque una
#     idea por id no está cubierto.
#   · Sólo mira ideas. Los desafíos se buscan por `policy_scope` en todos los
#     controllers, pero esto no lo verifica.
#   · Una idea a la que se llega por OTRO registro: `IdeaVersion.find(id).idea`,
#     `StepEntry.find(id).idea`.
#   · Lo que no nombra `Idea` ni `ideas` literal: `public_send(:ideas)`, una
#     variable que ya trae la relación (`rel = @challenge.ideas` en otro método
#     y después `rel.find`), `%Q{}` y heredocs.
#   · Desarmar el scope con algo que no sea `unscope`: `.except(:where)`,
#     `.rewhere(...)`.
#   · Sintaxis que confunde a un detector de texto y le esconde el resto de la
#     línea: una comilla doble dentro de un texto entre comillas simples, un
#     literal `?"`, una regex con `#` adentro, una interpolación con llaves y
#     comillas anidadas.
#   · Da falsos POSITIVOS, que obligan a mirar la línea y son la dirección
#     segura: una cadena partida (marca `@challenge.ideas` aunque el
#     `policy_scope(` esté en la línea de arriba) y una variable local llamada
#     `ideas`.
#
# Lo que prueba el comportamiento de verdad son los `[404, 404]` de
# `spec/requests/participant_rules_spec.rb`, ruta por ruta. Esto cuida que una
# ruta NUEVA no nazca con el orden al revés.
RSpec.describe "las ideas se tocan por policy_scope", type: :lint do
  # Lo que menciona una idea sin buscarla, cada uno con por qué. Se saca de la
  # línea lo que matchea, no la línea: lo que quede se sigue mirando.
  SIN_BUSCAR_UNA_IDEA = {
    /\bwhen Idea\b/ => "un `case` sobre la clase del objetivo no busca nada",
    /\.ideas\.new\(/ => "construir una idea nueva no busca ninguna existente",
    # Sin argumentos: `exists?(id: params[:id])` sí es una búsqueda, y un
    # oráculo. Con o sin paréntesis: `exists? id: x` también.
    /\.ideas\.submitted\.exists\?(?![ \t]*[(\w:@])/ => "«¿hay alguna postulada?» no busca por id ni devuelve una"
  }.freeze

  # Lo que va por el scope y después lo desarma.
  DESARMA_EL_SCOPE = /policy_scope\((?:Idea|[^()]*\bideas\b[^()]*)\)\s*\.\s*unscope/

  def infraccion?(linea)
    codigo = linea
             .chomp # `readlines` deja el `\n`, y con él `#.*\z` no llega al final
             # Un texto no es código, pero lo interpolado adentro sí.
             .gsub(/"(?:[^"\\]|\\.)*"/) { |texto| texto.scan(/#\{([^}]*)\}/).flatten.join(" ") }
             .gsub(/'(?:[^'\\]|\\.)*'/, " ")
             .sub(/#.*\z/, "") # ni los comentarios

    return true if codigo.match?(DESARMA_EL_SCOPE)

    # Con un espacio y no con nada: `@challenge.ideas.new(Idea.find(x))` sin
    # `.ideas.new(` quedaba `@challengeIdea.find`, y `\bIdea\b` no encuentra
    # el borde de la palabra.
    codigo = codigo.gsub(/policy_scope\((?:Idea|[^()]*\bideas\b[^()]*)\)/, " ")
    SIN_BUSCAR_UNA_IDEA.each_key { |permitido| codigo = codigo.gsub(permitido, " ") }

    codigo.match?(/\bIdea\b|\.ideas\b|^\s*ideas\b/)
  end

  it "marca las formas de buscar una idea sin policy_scope" do
    [
      "@idea = @challenge.ideas.find(params[:idea_id])",
      "idea = Idea.where(challenge_id: @challenge.id).find(params[:id])",
      "idea = Idea.find_by_id(params[:id])",
      "idea = @challenge.ideas.where(id: params[:id]).first!",
      "idea = Idea.find_sole_by(id: params[:id])",
      "idea = policy_scope(Challenge).first.ideas.find(params[:id])",
      "      .ideas",
      # Las que evadieron la segunda versión.
      "when Idea then Idea.find(id)",
      "@idea = @challenge.ideas.new(Idea.find(params[:origen]).payload)",
      "hay = @challenge.ideas.submitted.exists?(id: params[:id])",
      "hay = @challenge.ideas.submitted.exists? id: params[:id]",
      "flash[:notice] = \"Listo: \#{@challenge.ideas.find(params[:id]).title}\"",
      "      ideas.find(params[:id])",
      "@idea = policy_scope(Idea).unscoped.find(params[:id])",
      "@idea = policy_scope(@challenge.ideas).unscope(:where).find(params[:id])"
    ].each do |linea|
      expect(infraccion?(linea)).to be(true), "no la marcó: #{linea}"
    end
  end

  it "deja pasar lo que va por el scope o no busca ninguna" do
    [
      "@idea = policy_scope(@challenge.ideas).find(params[:idea_id])",
      "@idea = policy_scope(Idea).where(challenge_id: @challenge.id).find(params[:id])",
      "@idea = @challenge.ideas.new(author: current_user)",
      "redirect_to challenge_ideas_path(@challenge), notice: \"Idea eliminada.\"",
      "when Idea then challenge_idea_path(target.challenge, target)",
      "def locked? = @locked ||= @challenge.ideas.submitted.exists?",
      "# buscar con @challenge.ideas.find rompe esto",
      # Con el `\n` que deja `readlines`: sin él este caso pasaba en el test y
      # fallaba en el barrido real.
      "    # Por `policy_scope` y no `@challenge.ideas`: a quien participa\n"
    ].each do |linea|
      expect(infraccion?(linea)).to be(false), "la marcó de más: #{linea}"
    end
  end

  it "ningún controller toca una idea sin policy_scope" do
    infractores = Dir[Rails.root.join("app/controllers/**/*.rb")].sort.flat_map do |archivo|
      File.readlines(archivo).each_with_index.filter_map do |linea, indice|
        next unless infraccion?(linea)

        "#{archivo.delete_prefix("#{Rails.root}/")}:#{indice + 1}  #{linea.strip}"
      end
    end

    expect(infractores).to be_empty,
                           "Toca una idea sin policy_scope (a quien participa le confirma que existe).\n" \
                           "Si no busca ninguna, sumala a SIN_BUSCAR_UNA_IDEA con su razón:\n  " \
                           "#{infractores.join("\n  ")}"
  end
end
