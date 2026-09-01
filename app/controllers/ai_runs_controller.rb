# frozen_string_literal: true

# Auditoría de la IA: qué se pidió, qué respondió, cuánto costó, cuánto tardó.
#
# Existe desde el día 1 aunque el proveedor sea de fixtures — el rastro no
# cambia cuando se enchufe uno real.
class AiRunsController < ApplicationController
  def index
    authorize AiRun, :index?
    @runs = policy_scope(AiRun).includes(:challenge, :challenge_step, :idea, :requested_by)
                               .recent.limit(100)
    @stats = {
      total: policy_scope(AiRun).count,
      failed: policy_scope(AiRun).failed_ones.count,
      tokens: policy_scope(AiRun).sum("COALESCE(tokens_in, 0) + COALESCE(tokens_out, 0)"),
      avg_latency: policy_scope(AiRun).average(:latency_ms)&.round
    }
  end

  def show
    @run = policy_scope(AiRun).find(params[:id])
    authorize @run, :show?
  end
end
