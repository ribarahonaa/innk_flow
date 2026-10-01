# frozen_string_literal: true

module Flow
  module Workshops
    # Reparte grupos INDIVISIBLES de personas en mesas de a lo sumo `size`.
    #
    # No toca la base a propósito: recibe un hash y devuelve arreglos, así que
    # se prueba con datos pelados y el servicio que lo usa
    # (`Flow::Workshops::AssignGroups`) se queda con los guardas y la
    # persistencia.
    #
    # Idear no es otro algoritmo: es éste con un grupo por persona. Un
    # mecanismo y un gancho, igual que la mesa de una sola persona del modo
    # individual.
    class Seating
      Split = Data.define(:group_key, :shared_user_ids, :inside)
      Result = Data.define(:tables, :splits)

      def initialize(groups:, size:)
        # Un grupo sin nadie no arma mesa: en evolución una idea cuya única
        # persona está marcada ausente llega así, y dejarla pasar devolvía una
        # mesa vacía.
        @groups = groups.reject { |_, ids| ids.empty? }.transform_values(&:uniq)
        # Un tamaño menor que 1 no puede sentar a nadie: una mesa por persona
        # es lo más cerca que se puede estar de lo que se pidió.
        @size = [size.to_i, 1].max
      end

      def call
        splits = []
        bloques = clusters.flat_map { |keys| fit(keys, splits) }
        Result.new(tables: pack(bloques), splits: splits)
      end

      private

      # Componentes conexos sobre «comparten una persona». En idear no hay
      # ninguno: cada grupo es una persona distinta.
      def clusters
        restantes = @groups.keys.sort_by(&:to_s)
        out = []

        until restantes.empty?
          cola = [restantes.shift]
          racimo = []

          until cola.empty?
            key = cola.shift
            next if racimo.include?(key)

            racimo << key
            vecinos = restantes.select { |otra| (@groups[key] & @groups[otra]).any? }
            restantes -= vecinos
            cola.concat(vecinos)
          end

          out << racimo.sort_by(&:to_s)
        end

        out
      end

      # Un racimo, en bloques que entren. Recursivo porque lo que se desprende
      # puede no entrar tampoco.
      def fit(keys, splits)
        return [] if keys.empty?

        gente = personas(keys)
        return [gente] if gente.size <= @size

        # Una sola idea más grande que el tamaño: no hay frontera por donde
        # cortar, así que se parte su gente. Es el único caso en que el
        # resultado no respeta «no partir grupos», y por eso tiene su propio
        # aviso.
        if keys.size == 1
          splits << Split.new(group_key: keys.first, shared_user_ids: [], inside: true)
          return gente.each_slice(@size).to_a
        end

        # Se desprende la de MENOR solape con el resto; empate por menos gente,
        # después por clave. El orden de `clusters` ya entrega las claves
        # ordenadas, así que este último desempate no se puede observar desde
        # afuera: está para que `fit` no dependa de una invariante que se
        # establece en otro método.
        suelta = keys.min_by { |k| [solape(k, keys - [k]), @groups[k].size, k.to_s] }
        resto = keys - [suelta]
        compartida = @groups[suelta] & personas(resto)
        exclusiva = @groups[suelta] - compartida

        splits << Split.new(group_key: suelta, shared_user_ids: compartida, inside: false)

        # `exclusiva` vacía no arma mesa: la idea desprendida no tenía gente
        # propia. El aviso igual sale, porque la idea SÍ se quedó sin mesa
        # aparte y quien mire tiene que poder entenderlo.
        fit(resto, splits) + fit_exclusiva(suelta, exclusiva, splits)
      end

      def fit_exclusiva(key, gente, splits)
        return [] if gente.empty?
        return [gente] if gente.size <= @size

        splits << Split.new(group_key: key, shared_user_ids: [], inside: true)
        gente.each_slice(@size).to_a
      end

      def personas(keys) = keys.flat_map { |k| @groups[k] }.uniq

      def solape(key, otras) = (@groups[key] & personas(otras)).size

      # Los bloques chicos comparten mesa: juntar gente que no trabaja junta no
      # parte ningún grupo, y es lo que respeta el tamaño pedido. Primero los
      # grandes (first-fit decreciente), que es lo que deja menos mesas.
      def pack(bloques)
        mesas = []

        bloques.sort_by { |b| [-b.size, b.first.to_s] }.each do |bloque|
          mesa = mesas.find { |m| m.size + bloque.size <= @size }
          mesa ? mesa.concat(bloque) : mesas << bloque.dup
        end

        mesas
      end
    end
  end
end
