require "google"
require "./params"

module Utils::GoogleHelpers
  # Private key base64 encoded
  ENC_PRIVATE_KEY = ENV["GOOGLE_PRIVATE_KEY"]? ||
                    "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpQcm9jLVR5cGU6IDQsRU5DUllQVEVECkRFSy1JbmZvOiBERVMtRURFMy1DQkMsNUFFQzI5NEMyMUNGRTAwQwoKb0JXTUVKTlJUU3hHdWRpUFc1ODMwcnlrb1JaSzNEZnVSZ0hUOXdnL0RjMjR0ZW13eTNkMWRhNEZ3akg0d0RWYgp2dEdzWm14WFIwbFZCUFdLeHdacGh2Z0ZTRTM4dnl2VHduKyt3VHRFaWc2ZFBVTFE3VHRmclU5WDIxcG5MTmNBCk9jZytBQ0lONVNmZXRlSk0xWjBPOXMvN2FPN0ZLa0toNWI0Z0dwTEhrTWhiaGpnTng2ZStFWGwxOVBoaEkvSFoKdVlXQXVwWjNvOHhjUlVnMHIzWUNJaTRUdmlnRjJ4a2FDWURTMy9BUk9ZMlZzUU9Zc2R4SGZiaFo3Zm1tMzNvbgpSOC9WU0J3b2lkUEsxSWc3QUtvZEZQMlBkVDdibjg3YUM2MDBIN3gwclcwZ0ZodWlpMFNSc1ErWVBianVNcFRQCjBSVWZKSjNNSzN4anBzYmZwRW55VDlFcHZhZ2kweFBVYnY5TjNiQWVIdmU3U3ZqRlBVMnJyUkpONklMYmVkczgKN21udFo0VU9SZGhYeWJjZTJveTVsYjBvbnY5dFAyUitlTUw2SGdvcXlpMGJ1SjBsWnVnSEVKdUpYTlZOOXpJLwpGMjRoUU9nQlhQKzY1QzJxaUl5T3VoR2RjbVE4TlRNd2FsSkxzcFgrV2hKUkE2c2ViNUx0alJsamlIUWxvdHAwCnBqMGJsSm1kZ2lJVms2ckVhaEZwSW90Y2lmVStIV1FjR0RKVUNMeDJMK1ZrZ3paTzU2Mi9USjBBaVVibjRFeTkKNG1zeDF1UHVsYUY4T3NhOVN3MVhkZURFbHJSODBSRTNWbDFtNFNwb3p2WG1QSmgwRVVLbVJEdHB3VVZhYTNjMApsdXhoRzlEdVBLM0o5ZXB0MVpCcU9PeExldTQvTUNQRHE4STZ1SjM4UVNFTzdBQWZMdlY1OE51aFhOL1RUNnlpCmhKQlhVWTFuR043L3dSUlZVMlB2TEpTNDVNQ0s0Nlo1RWRyU3Ira3pPd1pNZmt2aU1GejFTQW5vN3ViQWNpS0sKZkFOTlA5ekZzYU9lM0ZBNVB5cXBnZ2JxcllHUnYvb0h0NUhRRnJveitUT3BjcHNSNUpuc1JZWEJxb2lZUVhqVwpxd2NORUJIOXRhMUNOczBHaDBiZFlEY2YzZ1VWZUx1ekxWVFFSSTBRekIrZDZJc2xQMjlLYlJMOSt3SFBOTGJGClBLb1JKQTFrNFpDRHVaRWllZDYwVS91VXFlTEcydzZjemZaNUVRQTdMeEllZytWZkVNcnhIcVlDQkpFTmxWY24KdmU1RUhtVVY3SUVjdVZKS1A0cG04M0NVanhlY2U2Y0tJR05qMUp6WmNuU2tad3RkRzhQZlJpaTFNMFcrdU10cgpRVjBBWUt5Q0xTZzBPQnNhYms1OVdUc0w5d0RmelRoWmRzYXJCcFFva2FHcjBnWkdDMDZhTEJ3YWdrYnlLTXJzCkZBRWVCQlRpSUt1c0tKU1lUSE1lNU1Sc0JNWEdnVFdCdlNNSU9EZHNBK3NIWVh6ZzAyaDNkaTlBNXc0WVoxaWwKajFURGVKSHk0eSsxVjRhNHZrWXRzZlZ4N0kybVhINWFPQSs0Rmd0TnQvbHhZUjRYWlNYWWR6QmFaQzQ1ejAwYgpROWtyNyt0QU1sRUYxZnAwOU5jWDJ4QzJEU2Fua1VkVFZlbDVVUVBWek5mSGgralhBWVhrY2VsdlJObUt6TUk5ClhRRlBWTHBnbGhVekdzRGt5cnNzVHNpNFFucENTN0k3SDMwVHFVNkVZcHRFMUlpc0NLeU1WMDhNRkdoakUxbkYKbFlUdjdPd1gveWRZQ3ZpUlJXcHNGa2ZsUjEyOXQ1anI3YTA3NmZubVdONWZoMUFYL2hUb3czdFhZa1p6d3VtZwpnQXJpR0tNSDY4WnNzd1ZLOWZEOFVGdE5WRGd2T1p0a1l0bkdKVXBYd1ByUGR1ZkM5RlB0ZW9HQ0lhVVR6VnpmCjVDemV1RGx5QWhiZHZjYTRaTURlOGxGK0ZsR2lWWk9lOWU5RDNWbDlGVk5KU3dmNU41VlRWTkxEOUwvMWZkQm0KZnFhS0YzSzlUWE9BTk1ZYldySWhweFN5TlpPSXJxTHgzWjdFWmdxZjUxVmtrOWhtQ2VnNDNCQVNRSEFOdnU0TgotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQ=="
  PRIVATE_KEY = String.new(Base64.decode(ENC_PRIVATE_KEY))

  ISSUER           = ENV["GOOGLE_ISSUER"]? || "placeos@organisation.iam.gserviceaccount.com"
  ADMIN_ACCOUNT    = ENV["GOOGLE_ADMIN_ACCOUNT"]? || "placeos_service_account@admin.org.com"
  DIRECTORY_DOMAIN = ENV["GOOGLE_DIRECTORY_DOMAIN"]? || "example.com"

  def calendar_for(sub = ADMIN_ACCOUNT)
    auth = Google::Auth.new(
      issuer: ISSUER,
      signing_key: PRIVATE_KEY,
      scopes: "https://www.googleapis.com/auth/calendar",
      sub: sub,
      user_agent: "PlaceOS Staff API"
    )

    Google::Calendar.new(auth: auth)
  end

  def google_directory
    auth = Google::Auth.new(
      issuer: ISSUER,
      signing_key: PRIVATE_KEY,
      scopes: "https://www.googleapis.com/auth/admin.directory.user.readonly",
      sub: ADMIN_ACCOUNT,
      user_agent: "PlaceOS Staff API"
    )

    Google::Directory.new(auth, DIRECTORY_DOMAIN)
  end

  # Callback to enforce JSON request body
  protected def ensure_json
    unless request.headers["Content-Type"]?.try(&.starts_with?("application/json"))
      render status: :not_acceptable, text: "Accepts: application/json"
    end
  end
end
