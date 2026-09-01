# frozen_string_literal: true

class AiRunPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  def index? = manager?
  def show? = manager?
end
