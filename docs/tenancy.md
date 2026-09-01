# Aislamiento por empresa

## Por qué esto existe

En `innk_r5` el scoping por `company_id` es 100% manual: `@company.ideas.find(...)`
escrito a mano en cada controller, sin red de seguridad. La suite de regresión
encontró ~50 fugas entre empresas. La causa no fue descuido puntual sino el
diseño: **toda defensa que dependa de que alguien se acuerde, falla**.

Acá hay cuatro capas. Las tres primeras dan ergonomía y errores tempranos.
**La cuarta hace la fuga imposible de escribir.**

---

## Capa 1 — `Current` + `Flow::Tenant`

`Current.company` es el tenant activo. Se establece de dos maneras:

```ruby
# Web: TenantResolution lo hace en un around_action, desde la sesión.
# Jobs, seeds, tasks: a mano, porque no hay request.
Flow::Tenant.with(company) { ... }
```

Y una sola válvula de escape:

```ruby
Flow::Tenant.bypass! { ... }   # levanta el scoping dentro del bloque
```

`bypass!` es explícito, acotado a un bloque y **greppable**. Está permitido en
`db/`, `lib/tasks/`, `app/jobs/` y en un puñado de archivos con la razón escrita
en `spec/lint/tenant_bypass_spec.rb`. Ese spec falla si aparece en otro lado.

**Nunca usar `.unscoped` para lo mismo.** Es invisible en un grep de tenancy y
además remueve los scopes de dominio, no solo el de empresa. El lint lo prohíbe.

---

## Capa 2 — `TenantScoped`

```ruby
class Challenge < ApplicationRecord
  include TenantScoped
end
```

Lo que aporta:

| | |
|---|---|
| `default_scope` | filtra por `Current.company_id` — y **revienta con `MissingTenant` si no hay tenant** |
| `before_validation` | asigna `company_id` desde el contexto |
| `tenant_matches_current` | impide escribir en otra empresa aun teniendo el objeto en memoria |
| `associations_within_tenant` | cada `belongs_to` a otro modelo scoped debe apuntar a la misma empresa — **corre incluso bajo `bypass!`**, es la red de jobs y seeds |

### La inversión que importa

```ruby
Current.company = nil
Membership.first   # => TenantScoped::MissingTenant
```

En r5, olvidarse de scopear devolvía **silenciosamente** los datos de todas las
empresas. Acá el olvido es ruidoso. Falla ruidosa > fuga silenciosa.

### El costo de `default_scope`

`default_scope` tiene fama de traicionero, con razón: contamina `Model.new`
(acá es deseable — asigna el tenant), se hereda en asociaciones, y `unscoped`
lo tira entero. La contrapartida es que un `has_many :through` dentro de un job
sin tenant revienta. **Eso es el diseño funcionando**, no un bug: todo job abre
con `Flow::Tenant.with(...)`.

---

## Capa 3 — Controllers

`TenantResolution` establece `Current` en un `around_action` y lo limpia siempre.

**Regla dura: 404, nunca 403, ante un recurso de otra empresa.** Un 403 confirma
que el recurso existe, y eso convierte cualquier listado de ids en un oráculo de
existencia cross-tenant.

---

## Capa 4 — La base de datos: FKs compuestas

Toda tabla de dominio lleva `company_id NOT NULL` y `UNIQUE (id, company_id)`.
Toda FK hacia otra tabla de dominio incluye `company_id`:

```sql
ALTER TABLE step_entries ADD CONSTRAINT step_entries_idea_same_company
  FOREIGN KEY (idea_id, company_id) REFERENCES ideas (id, company_id) ON DELETE CASCADE;
```

Atar una idea de la empresa A a un desafío de la B **es rechazado por Postgres**.
No "validado" — rechazado. Y encadena hasta las hojas: un `assessment_score` no
puede referenciar un criterio de otra empresa aunque el código lo intente.

### Cómo se escriben

Rails 7.1 no tiene DSL para FK compuesta (`add_foreign_key` no acepta arrays;
eso llegó en 7.2). Usar los helpers, nunca SQL a mano:

```ruby
tenant_table :challenge_steps do |t|
  t.references :challenge, null: false, type: :uuid, index: true
  t.integer :position, null: false
end
add_tenant_fk :challenge_steps, :challenges, column: :challenge_id
```

`tenant_table` crea la tabla con PK uuid, `company_id NOT NULL` indexado y el
`UNIQUE (id, company_id)` que las FKs necesitan como destino.

### Consecuencia: `schema_format = :sql`

`schema.rb` **no serializa FKs compuestas**: se perderían en cada `db:prepare` y
la garantía se evaporaría en silencio. Por eso el schema canónico es
`db/structure.sql` (`config/application.rb`). Costo aceptado: diffs más ruidosos.

Esto obliga a `postgresql-client-17` en las imágenes: el `pg_dump` 15 de Debian
bookworm se niega a dumpear un server 17. Ya está resuelto en los Dockerfiles.

---

## Capa 5 — RLS de Postgres: documentada, no implementada

Row-Level Security es la defensa más fuerte, pero exige `SET LOCAL flow.company_id`
por request y un rol no-superusuario. Con pooling transaccional (PgBouncer) y
Sidekiq multihilo es una fuente de bugs sutiles. Con las capas 2 y 4 es redundante
para una maqueta.

Si se decide implementarla:

```sql
ALTER TABLE ideas ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON ideas
  USING (company_id = current_setting('flow.company_id')::uuid);
```

…más un `SET LOCAL` en un `around_action` y en cada job, y un rol de aplicación
sin `BYPASSRLS`.

---

## Los 5 specs de guardia

| Spec | Qué impide |
|---|---|
| `spec/tenancy/model_coverage_spec.rb` | Un modelo nuevo sin decisión de tenencia. Recorre `ApplicationRecord.descendants` y exige `TenantScoped` o entrada en `GLOBAL_MODELS` **con la razón escrita** |
| `spec/tenancy/schema_spec.rb` | Una FK simple entre tablas de dominio. Introspecciona `pg_constraint` |
| `spec/tenancy/tenant_scoped_spec.rb` | Que el concern deje de reventar sin tenant, o permita escribir cruzado |
| `spec/tenancy/cross_tenant_requests_spec.rb` | Que un endpoint devuelva 200 (fuga) o 403 (oráculo) con un id ajeno. Recorre las rutas solo, así crece con cada fase |
| `spec/lint/tenant_bypass_spec.rb` | `bypass!` o `.unscoped` fuera de las rutas autorizadas |

### Los guardias muerden

No alcanza con que estén verdes. Verificado por mutación:

| Mutación | Resultado |
|---|---|
| Modelo de dominio sin `TenantScoped` | `model_coverage` falla y lo nombra: `- LeakyThing` |
| `.unscoped` en `app/models/membership.rb` | `lint` falla con archivo y línea: `app/models/membership.rb:22` |
| FK simple entre dos tablas con `company_id` | `schema_spec` falla: `mut_child.{parent_id} -> mut_parent` |

Al agregar una capa de defensa nueva, repetir el ejercicio: **un spec verde que
nunca vio rojo no prueba nada.**

---

## Modelos globales, y por qué

| Modelo | Razón |
|---|---|
| `Company` | Es el tenant mismo |
| `User` | Identidad global: el email es único en toda la instalación y el login ocurre antes de saber la empresa |
| `Identity` | Credencial de un `User` global; el lookup precede a `Current.company` |
| `Session` | Se resuelve **antes** de que exista `Current.company` — es lo que la establece |

La pertenencia vive en `Membership`, que **sí** es tenant-scoped. Eso permite que
una persona participe en varias empresas sin duplicar credenciales, y es lo que
hace posible el selector post-login sin resolver subdominios.

Preguntas intrínsecamente cross-tenant sobre un `User` (`companies_count`,
`all_memberships`) usan `bypass!` dentro de `User`, declarado en la allowlist.
