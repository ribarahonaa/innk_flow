# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Empresa #{n}" }
    sequence(:slug) { |n| "empresa-#{n}" }
  end

  factory :user do
    sequence(:email) { |n| "user#{n}@test.dev" }
    sequence(:name)  { |n| "Usuario #{n}" }
    password { "Test1234" }
  end

  factory :membership do
    company
    user
    role { "participant" }

    # `:owner` quedó como alias histórico de `:admin`: el rol se eliminó
    # porque daba los mismos permisos.
    trait(:owner)       { role { "admin" } }
    trait(:admin)       { role { "admin" } }
    trait(:evaluator)   { role { "evaluator" } }
    trait(:participant) { role { "participant" } }
    trait(:gestor)      { role { "gestor" } }
  end
end

FactoryBot.define do
  factory :challenge do
    sequence(:name) { |n| "Desafío #{n}" }
    brief { "Reducir la merma en bodega." }
    status { "draft" }
    ai_default_mode { "human" }

    trait(:running) { status { "running" } }
  end

  factory :challenge_step do
    challenge
    kind { "evaluation" }
    sequence(:position) { |n| n }

    trait(:ideation)  { kind { "ideation" } }
    trait(:evolution) { kind { "evolution" } }
    trait(:selection) { kind { "selection" } }
    trait(:reporting) { kind { "reporting" } }

    trait(:active)    { status { "active" } }
    trait(:completed) { status { "completed" } }
    trait(:skipped)   { status { "skipped" } }
  end
end

FactoryBot.define do
  factory :idea do
    challenge
    author { Flow::Tenant.bypass! { create(:user) } }
    status { "draft" }
    origin { "human" }
  end

  factory :form_field do
    challenge_step
    sequence(:label) { |n| "Campo #{n}" }
    field_type { "text" }
  end
end
