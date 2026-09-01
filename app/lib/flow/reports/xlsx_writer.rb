# frozen_string_literal: true

module Flow
  module Reports
    # Excel del reporte. Una hoja por dimensión.
    class XlsxWriter
      def initialize(data)
        @data = data
      end

      attr_reader :data

      def call
        package = Axlsx::Package.new
        package.use_autowidth = false
        workbook = package.workbook

        header = workbook.styles.add_style(b: true, bg_color: "EEF4FF", border: { style: :thin, color: "DDDDDD" })
        percent = workbook.styles.add_style(num_fmt: 10)

        funnel_sheet(workbook, header)
        ranking_sheet(workbook, header, percent)
        matrix_sheet(workbook, header)

        package.to_stream.read
      end

      private

      def funnel_sheet(workbook, header)
        workbook.add_worksheet(name: "Embudo") do |sheet|
          sheet.add_row %w[Módulo Tipo Estado Entraron Avanzaron Eliminadas], style: header
          data["funnel"].each do |row|
            sheet.add_row [row["name"], row["kind"], row["status"],
                           row["entered"], row["advanced"], row["eliminated"]]
          end
          sheet.column_widths 28, 14, 14, 12, 12, 12
        end
      end

      def ranking_sheet(workbook, header, percent)
        workbook.add_worksheet(name: "Ranking") do |sheet|
          sheet.add_row ["#", "Idea", "Autor", "Origen", "Estado", "Puntaje",
                         "Evaluaciones", "Versión evaluada", "Versión actual"], style: header
          data["ranking"].each do |row|
            sheet.add_row [row["rank"], row["title"], row["author"], row["origin"], row["status"],
                           row["score"], row["assessments"], row["version"], row["current_version"]],
                          style: [nil, nil, nil, nil, nil, percent, nil, nil, nil]
          end
          sheet.column_widths 5, 46, 22, 10, 12, 10, 13, 16, 15
        end
      end

      # En modo by_version cada celda lleva la versión que se evaluó: el
      # Excel no puede mentir sobre qué se juzgó.
      def matrix_sheet(workbook, header)
        matrix = data["matrix"]
        return if matrix["columns"].blank?

        workbook.add_worksheet(name: "Matriz") do |sheet|
          sheet.add_row ["Idea", "Versión actual"] + matrix["columns"].map { |c| c["name"] }, style: header
          matrix["rows"].each do |row|
            cells = row["cells"].map do |cell|
              next "—" if cell["score"].nil?

              value = "#{(cell['score'] * 100).round}%"
              cell["version"] ? "#{value} (#{cell['version']})" : value
            end
            sheet.add_row [row["title"], row["current_version"]] + cells
          end
          sheet.column_widths(*([46, 14] + matrix["columns"].map { 20 }))
        end
      end
    end
  end
end
