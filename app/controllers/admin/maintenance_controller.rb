class Admin::MaintenanceController < ApplicationController
  before_action :verify_token

  def clear_comments
    count = GeneratedComment.delete_all
    render json: { deleted: count }
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
