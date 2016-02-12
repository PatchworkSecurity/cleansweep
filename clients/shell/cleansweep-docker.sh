#!/bin/sh
#
# Register and update package data for Docker images
set -eu
IFS="$(printf '\t\n')"
VERBOSE=0
WEBSITE="https://patchworksecurity.com"
API_ENDPOINT="https://api.patchworksecurity.com/api/v1/machine"

API_KEY=${PATCHWORK_API_KEY:-}
NAME=${PATCHWORK_NAME:-}
UUID=${PATCHWORK_UUID:-}
CONFIG_DIR=${PATCHWORK_DIR:-.patchwork}
CONFIG_FILE="$CONFIG_DIR/uuid"
DOCKER_IMAGE=


#################################################
# Main script execution
# Globals:
#   UUID
#   NAME
#   API_KEY
#   CONFIG_FILE
#################################################
main()
{
  if [ -z "$UUID" ]; then
    # true if not explicitly set or can't read from config
    register "$NAME"
  fi

  log_verbose "PATCHWORK_API_KEY: $API_KEY"
  log_verbose "NAME: $NAME"
  log_verbose "CONFIG_FILE: $CONFIG_FILE"

  log "Using uuid: $UUID"
  log "Updating machine state"
  update "$UUID"
}

#################################################
# Register Docker image with Patchwork
# Globals:
#   API_ENDPOINT
#   CONFIG_DIR
#   UUID
# Arguments:
#   $1: machine name
#################################################
register()
{
  name="$1"

  read -r os version <<RELEASE_DATA
$(read_release_data)
RELEASE_DATA

  json=$(printf '{
    "name": "%s",
    "os": "%s",
    "version": "%s"
  }' "$name" "$os" "$version")

  # really naive json parsing
  awk_script='BEGIN {
    RS=","
    FS=":"
    status=1
  }
  (NF > 1) && ($1 ~ /"uuid"$/) {
    # split returns the string before, in and after the double quotes
    if (3 == split($2, parts, /"/)) {
      print parts[2]
      status=0
      exit
    }
  }
  END {
    exit status
  }'

  log "Registering new machine $name - ($os $version)"
  UUID=$(make_request "$API_ENDPOINT" "$json" | awk "$awk_script")

  if [ ! -d "$CONFIG_DIR" ]; then
    mkdir "$CONFIG_DIR"
  fi

  # save UUID
  echo "$UUID" > "$CONFIG_FILE"
}

#################################################
# Update set of packages for Docker image
# Globals:
#   API_ENDPOINT
# Arguments:
#   $1: machine uuid
#################################################
update()
{
  awk_script='BEGIN {
    RS="\n";
    FS="\t"
  }
  /^install ok installed/ {
    # output JSON object for installed packages
    # prefer source:Version, fallback to Version
    printf "{\"name\": \"%s\", \"version\": \"%s\"},\n", $2, ($3 ? $3 : $4)
  }'

  format='${Status}\t${Package}\t${source:Version}\t${Version}\n'
  pkgs=$(docker_run "dpkg-query -W -f '$format'" | awk "$awk_script")

  # remove trailing comma and turn into array
  pkgs="[ ${pkgs%,} ]"
  log_verbose "Uploading packages:\n$pkgs"

  ret=$(make_request "$API_ENDPOINT/$1" "$pkgs")
  log "Successfully upload data for\n\t$ret"
}

#################################################
# Perform a curl request against the API server
# Globals:
#   API_KEY
# Arguments:
#   $1: URL to curl against
#   $2: POST data
#   $@: Addtional curl arguments
# Returns:
#   Response body of request
#################################################
make_request()
{
  url="$1"
  data="$2"
  shift 2

  # read data from stdin, otherwise argument list may be too long
  curl -s -H "Authorization: $API_KEY" \
       -H "Expect: " \
       -H "Content-Type: application/json" \
       --fail \
       -d @- "$@" "$url" <<CURL_DATA
$data
CURL_DATA
}

#################################################
# Retrieve a value from lsb-release given a key
# Arguments:
#   $1: String to search
#   $2: Key to search for
# Returns:
#   Value associated with key
#################################################
parse_lsb_release()
{
  awk_script='BEGIN {
    FS="="
    status=1
  }
  (NF > 1) && ($1 == key) {
    print $2
    status=0
    exit
  }
  END {
    exit status
  }'

  echo "$1" | awk -v key="$2" "$awk_script"
}

#################################################
# Parse release files for os and version
# Globals:
#   WEBSITE
# Returns:
#   Tab-delimited (os, version) pair
#################################################
read_release_data()
{
  # read release data from files
  set +e
  release_data="$(docker_run 'cat /etc/lsb-release')"
  set -e

  if [ -n "$release_data" ]; then
    os=$(parse_lsb_release "$release_data" DISTRIB_ID)
    version=$(parse_lsb_release "$release_data" DISTRIB_RELEASE)
  else
    os="debian"
    version=$(docker_run 'cat /etc/debian_version' | awk -F'.' '{print $1}')
  fi

  os=$(echo "$os" | awk '{print tolower($0)}')

  if [ "$os" != "ubuntu" ] && [ "$os" != "debian" ]; then
    log "Sorry '$os' isn't supported at this time"
    log "Check $WEBSITE for supported operating systems"
    exit
  fi

  echo "$os\t$version"
}

#################################################
# Utility functions
#################################################
docker_run()
{
  docker run --rm --entrypoint=/bin/sh "$DOCKER_IMAGE" -c "$@"
}

usage()
{
  script=$(basename "$0")
  echo "Usage: $script [-v] IMAGE"
  exit
}

log()
{
  echo "  * $@"
}

log_verbose()
{
  if [ "$VERBOSE" -gt 0 ]; then
    log "$@"
  fi
}

exit_handler()
{
  if [ "$?" -ne 0 ]; then
    log "There was an error running the script"
  fi
}

trap exit_handler EXIT

while getopts ":v" opt; do
  case $opt in
    v)
      VERBOSE=$((VERBOSE+1))
      ;;
  esac
done
shift $((OPTIND-1))

if [ "$#" -lt 1 ]; then
  usage
fi
DOCKER_IMAGE="$1"
NAME=${NAME:-docker-$DOCKER_IMAGE}

if [ -z "$API_KEY" ]; then
  log "PATCHWORK_API_KEY must be set before running script\n\n" \
      "\texport PATCHWORK_API_KEY=your_api_key\n"
  log "Replace 'your_api_key' with the key you received during sign up"
  log "You can request a key at $WEBSITE"
  exit
fi

if [ -z "$UUID" ] && [ -f "$CONFIG_FILE" ]; then
  read -r UUID < "$CONFIG_FILE"
fi

# call main script at end to deal with network truncation when
# curl | sh
main
