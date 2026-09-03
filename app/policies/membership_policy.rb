# frozen_string_literal: true

# Quién administra la empresa administra a su gente.
class MembershipPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope; end

  def index? = manager?
  def create? = manager?
  def update? = manager?
  def destroy? = manager?
end
