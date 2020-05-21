# PlaceOS Staff API

## Env Vars

```
# Default Timezone
STAFF_TIME_ZONE=Australia/Sydney

# Google calendar credentials
GOOGLE_PRIVATE_KEY=base64
GOOGLE_ISSUER=placeos@organisation.iam.gserviceaccount.com
GOOGLE_ADMIN_ACCOUNT=placeos_service_account@admin.org.com
GOOGLE_DIRECTORY_DOMAIN=example.com

# Public key for decrypting and validating JWT tokens
SECRET_KEY_BASE=base64-public-key

# Location of PlaceOS API
PLACE_URI=https://example.place.technology

# Comma separated list of staff email domains
# for determining who is a potential guest
STAFF_DOMAINS=admin.org.com,org.com

# Database config:
PG_DATABASE_URL=postgresql://localhost/travis_test
```

## Local development

```
brew install postgres

# Setup the data store
sudo su
mkdir -p /usr/local/pgsql
chown steve /usr/local/pgsql
exit

initdb /usr/local/pgsql/data

# Then can start the service in the background
pg_ctl -D /usr/local/pgsql/data start

# Or start it in the foreground
postgres -D /usr/local/pgsql/data

# This seems to be required
createdb

# Now the server is running with default user the same as your Mac login
psql -c 'create database travis_test;'
export PG_DATABASE_URL=postgresql://localhost/travis_test
```
