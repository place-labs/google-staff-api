require "./spec_helper"
require "base64"

ENV["GOOGLE_PRIVATE_KEY"] = Base64.strict_encode("-----BEGIN RSA PRIVATE KEY-----\nMIICWgIBAAKBgH1rFiAsTRtg99/xdRLib32U03IxRFz93LMjjuxdGM+oGLLN9WmE\nsXVLUNaTVTVNwyHhXjKU2In1fGzqO4samNSEuLMYbKjpUkn7VjpbVqN5Z9mEVgjZ\noXu0RBs+uMQqB1iq7amfBt9kKIIWiqypfyd+8SQu1icUZzoXxkBYMyjpAgMBAAEC\ngYBfrPCNDJ6p0zhk+yLvjBO3PnBrfZAETJkvg2HFiGOkDj0BMkMUAukJbLI3bt+i\nsTa5wt4EQi5KWB5aS/mubVTGQJq91Qo/mNFfdfjpdAiLrTPWpcDrXWUBPX5ycvIR\nLl79DzaQWQ7CHOiQsX2P7dB3mjn/BYz/Tw6e1joQ7spWAQJBAL9fytFMPNTQ0Ew4\nMV3kKr/nYOGFeSuIcjY89avdfqf2gz0w6bDhuI3je5cXTWGX0ZnqhYYwUaNTE8NT\n0Jc6f0ECQQCnxXCBS5W4QohWUhPsL5gULFjcNSXiMSbE0hKtTSQMY/FJ0E/08yI4\nUZ+2qfHIK6LKemIOAhspjkZEbOki4mepAkB3V2BeVuGUgUd0UJKQj6oNFFg5Kwge\nGq/GnQtDCxRh3/uFnEwPLyPs79Bxr2llE8z04+gyf01ZwYQQieMJe8RBAkBi5qd9\n8Prf1ojcqiIId74lFkeD+OjOQL9kA5rzAqifjUMuili4Q6QGo0eNvP1FTUP4LNEl\nBOTSSIbvy2xcHi+RAkBl27EJAyYIBdwpQ2hxZ3rOyzp1PjQixZJP4LM7VRL+ThgF\nF2/Xb2Zm0CiUE4XXK/WMCEhVPFKdxcEHBFCW7dN5\n-----END RSA PRIVATE KEY-----")
ENV["GOOGLE_ISSUER"] = "placeos@organisation.iam.gserviceaccount.com"
ENV["GOOGLE_ADMIN_ACCOUNT"] = "placeos_service_account@admin.org.com"

module CalendarHelper
  extend self

  def mock_token
    WebMock.stub(:post, "https://www.googleapis.com/oauth2/v4/token")
      .to_return(body: {access_token: "test_token", expires_in: 3599, token_type: "Bearer"}.to_json)
  end

  def mock_calendar_list
    WebMock.stub(:get, "https://www.googleapis.com/calendar/v3/users/me/calendarList")
      .to_return(body: {
        "kind":          "calendar#calendarList",
        "etag":          "12121",
        "nextSyncToken": "TOKEN123",
        "items":         [{
          "kind":            "hi",
          "etag":            "12121",
          "id":              "cal2",
          "summary":         "example summary",
          "summaryOverride": "override",

          "hidden":   false,
          "selected": true,
          "primary":  true,
          "deleted":  false,
        }],
      }.to_json)
  end

  def mock_events
    WebMock.stub(:get, "https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=2500&singleEvents=true&timeMin=2016-02-15T10:20:30Z")
      .to_return(body: events_response.to_json)
  end

  def events_response
    {
      "kind":          "hi",
      "etag":          "12121",
      "summary":       "example summar",
      "updated":       Time.utc,
      "timeZone":      "Local",
      "accessRole":    "User",
      "nextSyncToken": "TOKEN123",
      "items":         [event_response],
    }
  end

  def mock_event
    WebMock.stub(:get, "https://www.googleapis.com/calendar/v3/calendars/primary/events/123")
      .to_return(body: event_response.to_json)
  end

  def mock_event_create
    WebMock.stub(:post, "https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1")
      .to_return(body: event_response.to_json)
  end

  def mock_event_update
    WebMock.stub(:patch, "https://www.googleapis.com/calendar/v3/calendars/primary/events/123456789?sendUpdates=None")
      .to_return(body: event_response.to_json)
  end

  def mock_event_delete
    WebMock.stub(:delete, "https://www.googleapis.com/calendar/v3/calendars/primary/events/123456789?sendUpdates=none&sendNotifications=false")
      .to_return(body: {"kind": "calendar#calendarDelete"}.to_json)
  end

  def mock_event_move
    WebMock.stub(:post, "https://www.googleapis.com/calendar/v3/calendars/original_calendar_id/events/event_id/move?destination=destination_calendar_id&sendUpdates=None")
      .to_return(body: event_response.to_json)
  end

  def event_response
    {
      "kind":     "test",
      "etag":     "12121",
      "id":       "123456789",
      "iCalUID":  "123456789",
      "htmlLink": "https://example.com",
      "updated":  Time.utc,
      "start":    {"dateTime": Time.utc},
      "creator":  {
        "email": "test@example.com",
      },
    }
  end
end

module DirectoryHelper
  extend self

  def mock_token
    WebMock.stub(:post, "https://www.googleapis.com/oauth2/v4/token")
      .to_return(body: {access_token: "test_token", expires_in: 3599, token_type: "Bearer"}.to_json)
  end

  def user_query_response
    {
      "kind":  "admin#directory#users",
      "users": [user_lookup_response],
    }
  end

  def mock_user_query
    WebMock.stub(:get, "https://www.googleapis.com/admin/directory/v1/users?domain=example.com&maxResults=500&projection=full&viewType=admin_view")
      .to_return(body: user_query_response.to_json)
  end

  def mock_lookup
    WebMock.stub(:get, "https://www.googleapis.com/admin/directory/v1/users/test@example.com?projection=full&viewType=admin_view")
      .to_return(body: user_lookup_response.to_json)
  end

  def user_lookup_response
    {
      "primaryEmail":               "test@example.com",
      "isAdmin":                    false,
      "isDelegatedAdmin":           false,
      "creationTime":               Time.utc,
      "agreedToTerms":              true,
      "suspended":                  false,
      "changePasswordAtNextLogin":  false,
      "includeInGlobalAddressList": false,
      "ipWhitelisted":              true,
      "isMailboxSetup":             true,
      "name":                       {
        "givenName":  "John",
        "familyName": "Smith",
        "fullName":   "John Smith",
      },
      "emails": [
        {
          "address": "test@example.com",
        },
      ],
    }
  end
end
