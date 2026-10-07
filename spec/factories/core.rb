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

  factory :workshop do
    sequence(:name) { |n| "Taller #{n}" }
    mode { "group" }
    status { "draft" }

    trait(:registered) { attendance_mode { "registered" } }
  end

  factory :workshop_challenge do
    workshop
    challenge
  end

  factory :workshop_group do
    workshop
    sequence(:name) { |n| "Mesa #{n}" }

    trait(:arrival) do
      arrival { true }
      name { "Mesa de llegada" }
    end
  end

  factory :workshop_group_member do
    workshop_group
    user { Flow::Tenant.bypass! { create(:user) } }
  end

  factory :workshop_proposal do
    workshop_group
    idea
    challenge_step
    payload { {} }
    status { "pending" }
  end

  factory :workshop_draft do
    workshop_group
    # Del MISMO taller que la mesa: dos factorías sueltas armarían un registro
    # que el modelo rechaza.
    workshop_challenge { association :workshop_challenge, workshop: workshop_group.workshop }
    payload { {} }
    updated_by factory: :user
  end
end
