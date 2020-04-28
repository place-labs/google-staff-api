# PlaceOS Staff API

## Env Vars

```
# Default Timezone
STAFF_TIME_ZONE=Australia/Sydney

# Google calendar credentials
GOOGLE_PRIVATE_KEY=base64
GOOGLE_ISSUER=placeos@organisation.iam.gserviceaccount.com
GOOGLE_ADMIN_ACCOUNT=placeos_service_account@admin.org.com

# Public key for decrypting and validating JWT tokens
SECRET_KEY_BASE=base64-public-key

# Location of PlaceOS API
PLACE_URI=https://example.place.technology

# Comma separated list of staff email domains
# for determining who is a potential guest
STAFF_DOMAINS=admin.org.com,org.com

# Database config:
PG_DATABASE_URL=postgres_database_url
```
