source "https://rubygems.org"

ruby "3.3.0"

# Mismas versiones que innk_r5: el equipo no cambia de terreno entre repos.
gem "rails", "7.1.3.4"
gem "pg", "~> 1.5"

# connection_pool 3.x exige Ruby >= 3.4 (usa "anonymous keyword rest
# parameter" dentro de un bloque, que en 3.3 es SyntaxError). Ruby acá es
# 3.3.0, igual que r5, y r5 pinnea lo mismo por la misma razón.
gem "connection_pool", "~> 2.4"
gem "puma", "~> 6.4"
gem "sprockets-rails"

# Vistas: HAML, igual que r5.
gem "haml-rails"
# Traducciones estándar de ActiveRecord/ActiveModel en español.
gem "rails-i18n", "~> 7.0"

# Async. La cola vive en Redis; sidekiq-unique-jobs evita que un retry
# duplique una llamada al LLM o una activación de step.
gem "sidekiq", "~> 7.2.4"
gem "sidekiq-unique-jobs", "~> 8.0"
gem "redis", "~> 5.0"

# Auth propia (Rails 7.1 no trae el generador `authentication` de Rails 8).
gem "bcrypt", "~> 3.1.7"

# Autorización por policies. NO CanCanCan: el ability.rb monolítico de r5
# es exactamente el archivo donde se escondieron las fugas cross-tenant.
gem "pundit"

# Fórmulas de evaluación definidas por el dueño del desafío.
# Parser propio en Ruby puro: la expresión NUNCA llega a eval/instance_eval.
gem "dentaku", "~> 3.5"

# Validación de la salida estructurada de la IA (mismo schema para el
# adapter de fixtures y para el proveedor real → no hay drift silencioso).
gem "json_schemer"

# El proveedor real. Se usa solo con FLOW_AI_PROVIDER=anthropic: el default
# sigue siendo el de fixtures, sin red ni API key.
gem "anthropic"

# Reportería
gem "caxlsx"
gem "caxlsx_rails"
gem "wicked_pdf", "~> 2.1"
# El binario de wkhtmltopdf. En innk_r5 esto es wkhtmltopdf-heroku en prod;
# acá alcanza el binario empaquetado (la maqueta no despliega).
gem "wkhtmltopdf-binary", "~> 0.12"

gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails"
  gem "dotenv-rails"
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "capybara-playwright-driver"
  gem "rack_session_access"
end
