# frozen_string_literal: true

class IdeaAttachment < ApplicationRecord
  include TenantScoped

  belongs_to :idea_version
  has_one_attached :file

  validates :field_key, presence: true
end
