class Admin::MaintenanceController < ApplicationController
  skip_forgery_protection
  before_action :verify_token

  def clear_comments
    count = GeneratedComment.delete_all
    render json: { deleted: count }
  end

  def refresh_comments
    unless ENV["ANTHROPIC_API_KEY"].present?
      return render json: { error: "ANTHROPIC_API_KEY not configured" }, status: :unprocessable_content
    end

    render json: CommentsRefreshService.new.call
  end

  private

  def verify_token
    expected = ENV["ADMIN_TOKEN"].presence
    provided = request.headers["X-Admin-Token"]
    unless expected && ActiveSupport::SecurityUtils.secure_compare(expected, provided.to_s)
      render json: { error: "unauthorized" }, status: :unauthorized
    end
  end
end
