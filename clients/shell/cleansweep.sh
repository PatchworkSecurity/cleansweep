#!/bin/sh
# This script implements machine registration and updates
set -eu
IFS=$'\n\t'
VERBOSE=0

# API_TOKEN must be supplied as an environment variable
# FRIENDLY_NAME defaults to hostname which may be sensitive.
# Set the FRIENDLY_NAME environment variable to override this.
API_TOKEN=${API_TOKEN:-}
API_ENDPOINT="https://api.patchworksecurity.com/api/v1/machine"
FRIENDLY_NAME=${FRIENDLY_NAME:-$(hostname)}
CONFIG_DIR=${CONFIG_DIR:-".patchwork"}
UUID_FILE="${CONFIG_DIR}/uuid"
UUID=${CLEANSWEEP_UUID:-}

log()
{
  # normal logs go to stdout
  echo "  * $@"
}

logv()
{
  # verbose logs go to stderr
  if [ "$VERBOSE" -eq 0 ]; then
    return
  fi

  log "$@" >&2
}

exit_handler()
{
  if [ "$?" != 0 ]; then
    log "There was an error running the script"
  fi
}

trap exit_handler EXIT


get_lsb_value()
{
  # Retrieve a value from lsb-release
  #
  # The awk script returns non-zero if the key wasn't found
  #
  # Returns:
  #   Value of supplied key or script error

  key=$1
  logv "Searching lsb-release for '$key'"

  # lsb-release is '='-delimited
  awk_script='BEGIN {
    FS="=";
  }
  /=/ {
    if ($1 == key) {
      value = $2
      key_found = 1
      exit
    }
  }
  END {
    if (key_found != 1) {
      exit 1
    }
    print value
  }'

  awk -v key="$key" "$awk_script" /etc/lsb-release
}


make_request()
{
  # Perform a curl request against the API server
  #
  # Args:
  #   url: URL to curl against
  #   $@: Addtional arguments to pass to curl
  #
  # Returns:
  #   Response body of request

  url=$1
  logv "Performing request to $url"
  shift

  curl -s -H "Authorization: $API_TOKEN" \
       -H "Expect: " \
       -H "Content-Type: application/json" \
       "$@" "$url"
}


register()
{
  # Register the current machine if it isn't registered
  #
  # Machine metadata is retrieved from /etc/lsb-release
  # and sent to the server. The server responds with a uuid
  # that the machine should use in future requests.
  #
  # Returns:
  #   Machine UUID or script error

  # Check that $CONFIG_DIR exists, otherwise saving
  # the uuid may fail
  if [ ! -d "$CONFIG_DIR" ]; then
    logv "Creating config directory"
    mkdir "$CONFIG_DIR"
  fi

  if [ -f "$UUID_FILE" ]; then
    logv "Machine is already registered"
    read -r uuid < "$UUID_FILE"
    echo "$uuid"
    return
  fi

  log "Registering new machine"
  os=$(get_lsb_value "DISTRIB_ID")
  version=$(get_lsb_value "DISTRIB_RELEASE")
  json=$(printf '{
    "name": "%s",
    "os": "%s",
    "version": "%s"
  }' "$FRIENDLY_NAME" "$os" "$version")

  logv "Machine $FRIENDLY_NAME ($os $version)"

  # We're expecting relatively well-formed JSON to be returned.
  # A JSON "key": "value" is considered a single record and the
  # fields are separated by the colon in the record. This approach
  # isn't robust enough to handle all JSON. A friendly name with
  # commas and colons may cause issues.
  awk_script='BEGIN {
    RS=",";
    FS=":";
  }
  /:/ {
    if ($1 ~ /"uuid"$/) {
      # split will return the string before, in and after the
      # double quotes
      count = split($2, parts, /"/)
      if (count == 3) {
        uuid = parts[2]
        uuid_found = 1
        exit
      }
    }
  }
  END {
    if (uuid_found != 1) {
      exit 1
    }
    print uuid
  }'

  # POSIX doesn't support set -o pipefail
  # awk will fail if make_request doesn't contain a uuid
  uuid=$(make_request "$API_ENDPOINT" --data "$json" | awk "$awk_script" -)

  logv "Saving uuid $uuid"
  echo "$uuid" > "$UUID_FILE"
  echo "$uuid"
}


update()
{
  # Updates the package set for the machine
  #
  # Package data is retrieved from dpkg-query and uploaded to the
  # service. This replaces the machine's previous package list

  log "Updating machine state"

  # output JSON like string
  pkgs=$(dpkg-query -W -f '{"name": "${Package}", "version": "${Version}"},\n')
  # remove trailing comma and turn into array
  pkgs="[ ${pkgs%,} ]"
  logv "Uploading packages:\n$pkgs"

  status=$(make_request "${API_ENDPOINT}/${UUID}" --data "$pkgs" \
                        -o /dev/null -w '%{http_code}')

  logv "Received HTTP $status"
  if [ "$status" -ne 200 ]; then
    log "Failed to update packages:  Received $status instead of 200"
  else
    log "Successfully uploaded package data"
  fi
}


if [ -z "$API_TOKEN" ]; then
  log "You didn't set an API_TOKEN"
  log "Please set one before running the script with\n\n" \
      "\texport API_TOKEN=your_token\n"
  log "Replace your_token with the token you received during sign up"
  log "You can request a token at https://patchworksecurity.com"
  exit 0
fi

if [ $# -gt 0 ]; then
  if [ "$1" = "-v" ]; then
    VERBOSE=1
    log "Verbose logging enabled"
  fi
fi

logv "API_TOKEN: $API_TOKEN"
logv "API_ENDPOINT: $API_ENDPOINT"
logv "FRIENDLY_NAME: $FRIENDLY_NAME"
logv "CONFIG_DIR: $CONFIG_DIR"
logv "UUID: ${CLEANSWEEP_UUID:-Not supplied}"

distro="$(get_lsb_value 'DISTRIB_ID')"
if [ "$distro" != 'Ubuntu' ]; then
  log "Sorry '$distro' isn't supported at this time"
  exit
fi


if [ -z "$UUID" ]; then
  UUID="$(register)"
fi

update
