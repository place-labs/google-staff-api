require "./spec_helper"

describe Staff do
  it "should return a list of users" do
    # instantiate the controller
    response = IO::Memory.new
    app = Staff.new(context("GET", "/api/staff/v1/people", HEADERS, response_io: response))
    DirectoryHelper.mock_token
    DirectoryHelper.mock_user_query

    # Test the instance method of the controller
    app.index
    response.to_s.split("\r\n").reject(&.empty?)[-1].should eq %([{"name":"John Smith","email":"test@example.com"}])
  end

  it "should the requested user" do
    # instantiate the controller
    response = IO::Memory.new
    ctx = context("GET", "/api/staff/v1/people/test@example.com", HEADERS, response_io: response)
    ctx.route_params = {"id" => "test@example.com"}
    app = Staff.new(ctx)
    DirectoryHelper.mock_token
    DirectoryHelper.mock_lookup

    # Test the instance method of the controller
    app.show
    response.to_s.split("\r\n").reject(&.empty?)[-1].should eq %({"name":"John Smith","email":"test@example.com"})
  end
end
