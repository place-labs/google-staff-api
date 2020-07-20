class Booking < Granite::Base
  connection pg
  table booking

  column id : Int64, primary: true # Primary key, defaults to AUTO INCREMENT

  column user_id : String
  column user_email : String
  column user_name : String
  column asset_id : String
  column zones : Array(String) = [] of String

  column booking_type : String
  column booking_start : Int64
  column booking_end : Int64
  column timezone : String?

  column title : String?
  column description : String?
  column checked_in : Bool = false

  column rejected : Bool = false
  column approved : Bool = false
  column approver_id : String?
  column approver_email : String?
  column approver_name : String?

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
      self.ext_data = extension_data.to_json
    elsif self.ext_data.presence.nil?
      self.ext_data = "{}"
    end
  end
end
