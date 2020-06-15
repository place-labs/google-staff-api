class Booking < Granite::Base
  connection pg
  table metadata

  column id : Int64, primary: true

  column user_id : String
  column user_email : String
  column user_name : String
  column asset_id : String

  column booking_type : String
  column booking_start : Time
  column booking_end : Time

  column title : String?
  column description : String?

  column ext_data : String?

  property extension_data : JSON::Any?

  def extension_data : JSON::Any
    if json_data = @extension_data
      json_data
    else
      data = self.ext_data
      @extension_data = data ? JSON.parse(data) : JSON.parse("{}")
    end
  end

  timestamps

  before_save :transform_extension_data

  def transform_extension_data
    if extension_data = @extension_data
      @ext_data = extension_data.to_json
    elsif @ext_data.nil? || @ext_data.try &.empty?
      @ext_data = "{}"
    end
  end
end
