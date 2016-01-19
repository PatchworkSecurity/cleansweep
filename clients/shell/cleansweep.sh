#!/bin/sh
# This script implements machine registration and updates
set -eu
IFS=$'\n\t'
VERBOSE=0
WEBSITE="https://patchworksecurity.com"

# PATCHWORK_API_KEY must be supplied as an environment variable
# FRIENDLY_NAME defaults to hostname which may be sensitive.
# Set the FRIENDLY_NAME environment variable to override this.
PATCHWORK_API_KEY=${PATCHWORK_API_KEY:-}
API_ENDPOINT="https://api.patchworksecurity.com/api/v1/machine"
FRIENDLY_NAME=${FRIENDLY_NAME:-$(hostname)}
CONFIG_DIR=${CONFIG_DIR:-".patchwork"}
UUID_FILE="${CONFIG_DIR}/uuid"
UUID=${PATCHWORK_UUID:-}
LSB_RELEASE="/etc/lsb-release"


run_script()
{
  # Wrap the script in a function to prevent undefined behavior from
  # network truncation

  check_requirements

  if [ $# -gt 0 ]; then
    if [ "$1" = "-v" ]; then
      VERBOSE=1
      log "Verbose logging enabled"
      log_settings
    fi
  fi

  if [ -z "$UUID" ]; then
    get_uuid_or_register
    logv "UUID: $UUID"
  fi

  update
}

register()
{
  # Register the current machine and return its UUID or error
  json=$(printf '{
    "name": "%s",
    "os": "%s",
    "version": "%s"
  }' "$FRIENDLY_NAME" "$OS" "$VERSION")

  # Handle JSON in the form of {"key": "value", "key2": "value2"}
  # This work for {"name": "friendly,name", "uuid": UUID} by chance
  awk_script='BEGIN {
    RS=",";
    FS=":";
  }
  /:/ {
    if ($1 ~ /"uuid"$/) {
      # split returns the string before, in and after the double quotes
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
  uuid=$(make_request "$API_ENDPOINT" "$json" | awk "$awk_script" -)

  echo "$uuid"
}

update()
{
  # Replaces this machines package set on the server or error

  log "Updating machine state"

  awk_script='BEGIN {
    RS="\n";
    FS="\t";
  }
  /^install ok installed/ {
    # output JSON like string if package is installed
    printf "{\"name\": \"%s\", \"version\": \"%s\"},\n", $2, $3;
  }'

  pkgs=$(dpkg-query -W -f '${Status}\t${Package}\t${Version}\n' | awk "$awk_script" -)
  # remove trailing comma and turn into array
  pkgs="[ ${pkgs%,} ]"
  logv "Uploading packages:\n$pkgs"

  # --fail handles most server errors and will trigger exit_handler
  machine=$(make_request "${API_ENDPOINT}/${UUID}" "$pkgs" --fail)
  log "Successfully uploaded data for machine $machine"
}


get_uuid_or_register()
{
  # try reading from old variable name
  UUID=${CLEANSWEEP_UUID:-}

  if [ -z "$UUID" ]; then
    if [ ! -d "$CONFIG_DIR" ]; then
      logv "Creating config directory"
      mkdir "$CONFIG_DIR"
    fi

    if [ ! -f "$UUID_FILE" ]; then
      log "Registering new machine - $FRIENDLY_NAME ($OS $VERSION)"
      echo "$(register)" > "$UUID_FILE"
    fi

    log "Using UUID from $UUID_FILE"
    read -r UUID < "$UUID_FILE"
  else
    log "CLEANSWEEP_UUID will be deprecated in version 3.0.0"
    log "Please update your code to use\n\n" \
        "\tPATCHWORK_UUID\n"
  fi
}

get_lsb_value()
{
  # Returns corresponding value for a key in lsb-release or error

  key=$1
  logv "Searching lsb-release for '$key'"

  awk_script='BEGIN {
    FS="="; # lsb-release is =-delimited
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

  awk -v key="$key" "$awk_script" "$LSB_RELEASE"
}

make_request()
{
  # Perform a curl request against the API server
  #
  # Args:
  #   url: URL to curl against
  #   data: POST data
  #   $@: Addtional arguments to pass to curl
  #
  # Returns:
  #   Response body of request

  url=$1
  logv "Performing request to $url"
  data=$2
  shift 2

  # use heredoc otherwise curl argument list may be too long
  curl -s -H "Authorization: $PATCHWORK_API_KEY" \
       -H "Expect: " \
       -H "Content-Type: application/json" \
       -d @- "$@" "$url" <<CURL_DATA
$data
CURL_DATA
}

check_requirements()
{
  # fail if any prerequisites aren't met
  if [ -z "$PATCHWORK_API_KEY" ]; then
    log "You didn't set PATCHWORK_API_KEY"
    log "Set this before running the script with\n\n" \
        "\texport PATCHWORK_API_KEY=your_api_key\n"
    log "Replace 'your_api_key' with the key you received during sign up"
    log "You can request a key at $WEBSITE"
    exit
  fi

  if [ ! -f "$LSB_RELEASE" ]; then
    log "$LSB_RELEASE doesn't exist"
    log "Check $WEBSITE for supported operating systems"
    exit
  fi

  OS=$(get_lsb_value "DISTRIB_ID")
  VERSION=$(get_lsb_value "DISTRIB_RELEASE")
  if [ "$OS" != 'Ubuntu' ]; then
    log "Sorry '$OS' isn't supported at this time"
    exit
  fi
}

log()
{
  echo "  * $@"
}

logv()
{
  if [ "$VERBOSE" -eq "1" ]; then
    log "$@" >&2
  fi
}

log_settings()
{
  logv "PATCHWORK_API_KEY: $PATCHWORK_API_KEY"
  logv "API_ENDPOINT: $API_ENDPOINT"
  logv "FRIENDLY_NAME: $FRIENDLY_NAME"
  logv "CONFIG_DIR: $CONFIG_DIR"
}

exit_handler()
{
  if [ "$?" -ne "0" ]; then
    log "There was an error running the script"
  fi
}

trap exit_handler EXIT

run_script "$@"
