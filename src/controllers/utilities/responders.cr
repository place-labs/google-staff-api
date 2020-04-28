require "http"

module Utils::Responders
  # Shortcut to save a record and render a response
  def save_and_respond(resource, create = true)
    if resource.save
      render json: resource, status: create ? HTTP::Status::CREATED : HTTP::Status::OK
    else
      render json: resource.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  # Merge fields into object
  def with_fields(model, fields) : Hash
    attrs = Hash(String, JSON::Any).from_json(model.to_json)
    attrs.merge(fields)
  end

  # Restrict model attributes
  def restrict_attributes(
    model,
    only : Array(String)? = nil,   # Attributes to keep
    except : Array(String)? = nil, # Attributes to exclude
    fields : Hash? = nil           # Additional fields
  ) : Hash
    # Necessary for fields with converters defined
    attrs = Hash(String, JSON::Any).from_json(model.to_json)
    attrs.select!(only) if only
    attrs.reject!(except) if except

    fields && !fields.empty? ? attrs.merge(fields) : attrs
  end
end
