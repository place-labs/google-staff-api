require "../spec_helper"

describe Staff do
  it "should return a list of users" do
    # instantiate the controller
    ctx = context("GET", "/api/staff/v1/people", HEADERS)
    ctx.response.output = IO::Memory.new
    app = Staff.new(ctx)
    DirectoryHelper.mock_token
    DirectoryHelper.mock_user_query

    # Test the instance method of the controller
    app.index
    ctx.response.output.to_s.should eq %([{"name":"John Smith","email":"test@example.com"}])
  end

  it "should the requested user" do
    # instantiate the controller
    ctx = context("GET", "/api/staff/v1/people/test@example.com", HEADERS)
    ctx.route_params = {"id" => "test@example.com"}
    ctx.response.output = IO::Memory.new
    app = Staff.new(ctx)
    DirectoryHelper.mock_token
    DirectoryHelper.mock_lookup

    # Test the instance method of the controller
    app.show
    ctx.response.output.to_s.should eq %({"name":"John Smith","email":"test@example.com"})
  end
end
