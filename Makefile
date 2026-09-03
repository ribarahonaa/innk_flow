.PHONY: help up down restart reup rebuild build ps logs logs-app logs-sidekiq logs-db \
	rails shell bash yarn-build yarn-install psql \
	migrate rollback seed setup clean-challenges \
	workers-restart task rake exec restart-service \
	test-build test-up test-down test-clean test-shell db-prepare-test spec spec-file spec-line test

# Atajos de docker compose. Espeja el Makefile de innk_r5.
COMPOSE ?= docker compose
COMPOSE_TEST ?= docker compose --profile test
APP_SERVICE ?= app
TEST_SERVICE ?= app_test
DB_SERVICE ?= db

help:
	@echo ""
	@echo "innk_flow — atajos (make <target>)"
	@echo ""
	@echo "Core:"
	@echo "  setup              Primera vez: build + up + db:prepare + seed"
	@echo "  up / down / reup   Levantar / bajar / reinicio limpio"
	@echo "  rebuild            Rebuild de imágenes + up"
	@echo "  ps / logs          Estado / logs de todos los servicios"
	@echo ""
	@echo "Rails:"
	@echo "  rails              Consola Rails"
	@echo "  shell              bash en el container app"
	@echo "  migrate / rollback db:migrate / db:rollback"
	@echo "  seed               db:seed (empresa demo + desafío completo)"
	@echo "  clean-challenges   Borra los desafíos; deja empresas, usuarios y criterios"
	@echo "  psql               psql contra innk_flow_development"
	@echo "  task TASK='<t>'    Cualquier task de rails"
	@echo ""
	@echo "Frontend:"
	@echo "  yarn-build         Recompilar bundles JS/CSS (tras tocar app/javascript o scss)"
	@echo "  yarn-install       Instalar deps JS"
	@echo ""
	@echo "Tests (servicio app_test):"
	@echo "  test-build         Build de la imagen de test"
	@echo "  test               db:prepare + suite completa"
	@echo "  spec               Suite completa (asume DB lista)"
	@echo "  spec-file FILE=<p> Un archivo"
	@echo "  spec-line FILE=<p> LINE=<n>   Un solo ejemplo"
	@echo "  screens            Recorrido visual con Playwright -> tmp/screenshots/"
	@echo ""
	@echo "  La app queda en http://localhost:3001"
	@echo ""

setup:
	$(COMPOSE) build
	$(COMPOSE) up -d --remove-orphans
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails db:prepare
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails db:seed
	$(COMPOSE) exec $(APP_SERVICE) yarn build
	@echo ""
	@echo "  Listo. http://localhost:3001 — login: admin@demo.test / Test1234"
	@echo ""

up:
	$(COMPOSE) up -d --remove-orphans

down:
	$(COMPOSE) down --remove-orphans

restart:
	$(COMPOSE) restart

reup:
	$(COMPOSE) down --remove-orphans
	$(COMPOSE) up -d --remove-orphans

rebuild:
	$(COMPOSE) up -d --build --remove-orphans

build:
	$(COMPOSE) build

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=200

logs-app:
	$(COMPOSE) logs -f --tail=200 $(APP_SERVICE)

logs-sidekiq:
	$(COMPOSE) logs -f --tail=200 sidekiq

logs-db:
	$(COMPOSE) logs -f --tail=200 $(DB_SERVICE)

rails:
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails c

shell:
	$(COMPOSE) exec $(APP_SERVICE) bash

bash: shell

yarn-build:
	$(COMPOSE) exec $(APP_SERVICE) yarn build

yarn-install:
	$(COMPOSE) exec $(APP_SERVICE) yarn install --check-files

migrate:
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails db:migrate

rollback:
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails db:rollback

seed:
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails db:seed

clean-challenges:
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails flow:limpiar_desafios

psql:
	$(COMPOSE) exec $(DB_SERVICE) psql -U postgres -d innk_flow_development

workers-restart:
	$(COMPOSE) restart sidekiq

task:
	@test -n "$(TASK)" || (echo "Falta TASK='<rails task>' (ej. TASK='tmp:clear')"; exit 2)
	$(COMPOSE) exec $(APP_SERVICE) ./bin/rails $(TASK)

rake:
	@test -n "$(TASK)" || (echo "Falta TASK='<rake task>' (ej. TASK='about')"; exit 2)
	$(COMPOSE) exec $(APP_SERVICE) bundle exec rake $(TASK)

restart-service:
	@test -n "$(SERVICE)" || (echo "Falta SERVICE=<name>"; exit 2)
	$(COMPOSE) restart $(SERVICE)

exec:
	@test -n "$(SERVICE)" || (echo "Falta SERVICE=<name>"; exit 2)
	@test -n "$(CMD)" || (echo "Falta CMD='<command>'"; exit 2)
	$(COMPOSE) exec $(SERVICE) sh -lc "$(CMD)"

# ─── Tests ───────────────────────────────────────────────────────────────
test-build:
	$(COMPOSE_TEST) build $(TEST_SERVICE)

test-up:
	$(COMPOSE_TEST) up -d $(TEST_SERVICE)

test-down:
	$(COMPOSE_TEST) stop $(TEST_SERVICE)

# Recorrido visual contra la app corriendo. Deja las capturas en
# tmp/screenshots/ y falla si alguna pantalla tira error de JS o HTTP >= 400.
screens:
	@mkdir -p tmp/screenshots
	docker run --rm --network host \
		-v "$(PWD)/tmp/screenshots:/shots" \
		-v "$(PWD)/script:/script:ro" -w /run \
		mcr.microsoft.com/playwright:v1.62.0-noble \
		bash -c "mkdir -p /run && cd /run && npm i -s playwright@1.62.0 >/dev/null 2>&1 && NODE_PATH=/run/node_modules node /script/capture_screens.js"

test-clean:
	$(COMPOSE_TEST) down --remove-orphans

test-shell:
	$(COMPOSE_TEST) exec $(TEST_SERVICE) bash

db-prepare-test:
	$(COMPOSE_TEST) run --rm $(TEST_SERVICE) bundle exec rails db:prepare

spec:
	$(COMPOSE_TEST) run --rm $(TEST_SERVICE) bundle exec rspec

spec-file:
	@test -n "$(FILE)" || (echo "Falta FILE='<spec path>'"; exit 2)
	$(COMPOSE_TEST) run --rm $(TEST_SERVICE) bundle exec rspec $(FILE) --format documentation

spec-line:
	@test -n "$(FILE)" || (echo "Falta FILE='<spec path>'"; exit 2)
	@test -n "$(LINE)" || (echo "Falta LINE=<number>"; exit 2)
	$(COMPOSE_TEST) run --rm $(TEST_SERVICE) bundle exec rspec $(FILE):$(LINE)

test:
	$(COMPOSE_TEST) run --rm $(TEST_SERVICE) bundle exec rails db:prepare
	$(COMPOSE_TEST) run --rm $(TEST_SERVICE) bundle exec rspec
