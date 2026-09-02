# frozen_string_literal: true

# La bandeja de avisos de quien está mirando.
#
# No hay policy de recurso: una notificación es de una sola persona y el scope
# la acota a ella. Autorizar por membresía sería más laxo que el propio scope.
class NotificationsController < ApplicationController
  skip_after_action :verify_pundit_usage, raise: false

  def index
    @notifications = mine.recent.includes(:challenge, :challenge_step, :idea).limit(50)
    @unread = mine.unread.count
  end

  # Abrir el aviso lo marca leído y lleva a donde se hace algo con él.
  def show
    notification = mine.find(params[:id])
    notification.read!

    redirect_to notification.path || notifications_path
  end

  def read_all
    mine.unread.find_each(&:read!)
    redirect_to notifications_path, notice: "Todo marcado como leído."
  end

  private

  def mine = Notification.where(user_id: current_user.id)
end
