require File.dirname(__FILE__) + '/../../test_helper'
require 'management/management_controller'

# Re-raise errors caught by the controller.
class Management::ManagementController; def rescue_action(e) raise e end; end

class Management::ManagementControllerTest < Test::Unit::TestCase
  def setup
    @controller = Management::ManagementController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  # Replace this with your real tests.
  def test_truth
    assert true
  end
end
