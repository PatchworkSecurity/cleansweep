#!/bin/sh
# This script implements machine registration and updating
set -eu
IFS=$'\n\t'

# API_TOKEN must be supplied as an environment variable
# The other variables have a default value
#
# NOTE:
#   FRIENDLY_NAME defaults to the machine's hostname. This may be
#   sensitive information in some circumstances.
API_ENDPOINT=${API_ENDPOINT:-"https://api.patchworksecurity.com/api/v1/machine"}
FRIENDLY_NAME=${FRIENDLY_NAME:-$(hostname)}
CONFIG_DIR=${CONFIG_DIR:-".patchwork"}

log()
{
  echo "$@" >&2
}

exit_handler()
{
  # awk will fail if it doesn't find expected data
  # and cause the script to exit due to set -e
  # This handler provides some feedback when that happens

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

get_uuid()
{
  # Register the current machine or retrieve machine uuid
  #
  # The current machine's uuid is stored in a subdirectory of where the
  # script executes. A new uuid can be obtained by deleting uuid_file
  #
  # Returns:
  #   UUID of the current machine

  uuid_file="${CONFIG_DIR}/uuid"
  if [ ! -f "$uuid_file" ]; then
    # Create the directory first otherwise we may register and not be
    # able to store the uuid
    if [ ! -d "$CONFIG_DIR" ]; then
      mkdir "$CONFIG_DIR"
    fi

    uuid=$(register)
    log "Registered with uuid $uuid"
    echo "$uuid" > "$uuid_file"
  else
    read -r uuid < "$uuid_file"
    log "Found previously registered uuid $uuid"
  fi

  echo "$uuid"
}

make_request()
{
  # Perform a curl request against the API server
  #
  # Args:
  #   url: URL to POST against
  #   $@: Addtional arguments to pass to curl
  #
  # Returns:
  #   Response body of request

  url=$1
  shift
  curl -s -H "Authorization: $API_TOKEN" \
       -H "Expect: " \
       -H "Content-Type: application/json" \
       "$@" "$url"
}


register()
{
  # Register the current machine
  #
  # The relevant machine metadata is retrieved from /etc/lsb-release
  # and sent to the server. The response is parsed to obtain the
  # uuid
  #
  # Returns:
  #   Machine UUID or script error

  os=$(get_lsb_value "DISTRIB_ID")
  version=$(get_lsb_value "DISTRIB_RELEASE")
  json=$(printf '{
    "name": "%s",
    "os": "%s",
    "version": "%s"
  }' "$FRIENDLY_NAME" "$os" "$version")

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
      # there should be 3 fields when we split "UUID", on a double
      # quote
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

  # POSIX doesn't support set -o pipefail, but the awk script will
  # error if make_request fails.
  make_request "$API_ENDPOINT" --data "$json" | awk "$awk_script" -
}

update()
{
  # Updates the package set for the current machine
  #
  # Package data is retrieved from dpkg-query and uploaded to the
  # service. This replaces the previous list of packages for this
  # machine.

  uuid=$(get_uuid)
  pkgs=$(dpkg-query -W -f '{"name": "${Package}", "version": "${Version}"},\n')
  # remove trailing comma
  pkgs=${pkgs%,}

  status=$(make_request "${API_ENDPOINT}/${uuid}" --data "[ $pkgs ]" \
                        -o /dev/null -w '%{http_code}')

  if [ "$status" -ne 200 ]; then
    log "Update received $status instead of 200"
  else
    log "Successfully uploaded package data"
  fi
}

if [ "$(get_lsb_value 'DISTRIB_ID')" != 'Ubuntu' ]; then
  log "Sorry only Ubuntu is currently supported"
else
  update
fi
