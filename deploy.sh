#!/usr/bin/env bash

# Bash Strict Mode
# set -o nounset
# set -o errexit
# set -o pipefail
# set -o errtrace
# IFS=$'\n\t'
# trap 'echo "Aborting due to errexit on line $LINENO. Exit code: $?" >&2' ERR

###############################################################################
# Environment
###############################################################################

_ME=$(basename "${0}")
_USERNAME="GozaRuu"
_BOX_NAME="dry_run"
_PROVIDER_NAME="virtualbox"
_VERSION="0.0.0"
: "${VAGRANT_CLOUD_TOKEN:?is not set}"
: "${DRY_RUN:?is not set}"

###############################################################################
# Help
###############################################################################

_print_help() {
  cat << HEREDOC
    ____   __  ___ _____    ____ _   __ ______ ______ ____   ____   ____
   / __ \\ /  |/  // ___/   /  _// | / //_  __// ____// __ \\ / __ \\ / __ \\
  / /_/ // /|_/ / \\__ \\    / / /  |/ /  / /  / __/  / /_/ // / / // /_/ /
 / ____// /  / / ___/ /  _/ / / /|  /  / /  / /___ / _, _// /_/ // ____/
/_/    /_/  /_/ /____/  /___//_/ |_/  /_/  /_____//_/ |_| \\____//_/

Repackage and deploy the $_BOX_NAME/$_USERNAME Vagrant box to Vagrant Cloud
Usage:
  ${_ME} [<arguments>]
  ${_ME} -h | --help
Options:
  -h --help  Show this screen.
HEREDOC
}

###############################################################################
# Script Functions
###############################################################################

_read_create_args() {
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      *)
        echo "Unknown argument recieved"
        _print_help
        exit 1
        shift
        ;;
    esac
  done

  _VERSION="1.0.0"
}

_read_upgrade_args() {
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      -ma | --major)
        _VERSION=$(echo "$_CURRENT_VERSION" | awk -F. '{$1++;print}' | sed -E 's/ /./g')
        shift
        ;;
      -mi | --minor)
        _VERSION=$(echo "$_CURRENT_VERSION" | awk -F. '{$2++;print}' | sed -E 's/ /./g')
        shift
        ;;
      -p | --patch)
        _VERSION=$(echo "$_CURRENT_VERSION" | awk -F. '{$3++;print}' | sed -E 's/ /./g')
        shift
        ;;
      *)
        echo "Unknown argument recieved"
        _print_help
        exit 1
        shift
        ;;
    esac
  done

  if [ "$_VERSION" == "" ] || [ "$_CURRENT_VERSION" == "$_VERSION" ]; then
    echo "no version section was specified"
    _print_help
    exit 1
  fi
}

_read_revert_args() {
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      -l | --latest)
        _VERSION=$_CURRENT_VERSION
        shift
        ;;
      -v | --version)
        shift
        if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          echo "FATAL: Given version is not a Semantic Version."
          exit 1
        fi
        _VERSION=$1
        shift
        ;;
      *)
        echo "Unknown argument recieved"
        _print_help
        exit 1
        shift
        ;;
    esac
  done

  if [ "$_VERSION" == "" ] || [ "$_CURRENT_VERSION" == "$_VERSION" ]; then
    echo "no version section was specified"
    _print_help
    exit 1
  fi
}
_get_json_field() {
  echo $1
  python -c 'import sys, json; print json.load(sys.stdin)['"$1"']'
}

_assert_request_success() {
  local _SUCCESS
  local _ERROR
  _SUCCESS=$(_get_json_field 'success')
  if [ "$_SUCCESS" == "false" ]; then
    _ERROR=$(_get_json_field "error")
    echo "FATAL: request failed. Error:$_ERROR"
    exit 1
  fi
}

_get_current_version() {
  _CURRENT_VERSION=$(vagrant box list | grep "$_BOX_NAME" || : | sed -E 's/.*\(virtualbox, (.*)\)/\1/')
}

_safely_run() {
  _COMMAND=""
  if [[ "$DRY_RUN" != "false" ]]; then
    printf -v _COMMAND "%q " "$@"
    echo "DRYRUN: Not executing $_COMMAND" >&2
  else
    "$@"
  fi
}

_repackage_box() {
  _safely_run vagrant box repackage "${_BOX_NAME}_${_VERSION}" "$_PROVIDER_NAME" "$_VERSION"

  if [ "$DRY_RUN" == "false" ] && [ ! -f "./${_BOX_NAME}_${_VERSION}.box" ]; then
    echo "FATAL: Could not repackage box"
    exit 1
  fi
}

_package_box() {
  echo "packaging currently running VM in $_PROVIDER_NAME as ./$_BOX_NAME.box"
  _safely_run vagrant package --output "${_BOX_NAME}_${_VERSION}.box"

  if [ "$DRY_RUN" == "false" ] && [ ! -f "./${_BOX_NAME}_${_VERSION}.box" ]; then
    echo "FATAL: Could not package box. Make sure the VM you want to package is running in $_PROVIDER_NAME"
    exit 1
  fi
}

_create_box_url() {
  echo "creating box $_BOX_NAME for user $_USERNAME"
  local _RESPONSE

  echo "fetching $_VERSION upload URL"
  _RESPONSE=$(_safely_run curl \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    "https://app.vagrantup.com/api/v1/boxes" \
    --data '{ "box": { "username": "'"$_USERNAME"'", "name": "'"$_BOX_NAME"'" } }')

  echo "$_RESPONSE" | _assert_request_success
}

_create_box_version_url() {
  local _RESPONSE

  echo "creating url for version $1"
  _RESPONSE=$(
    _safely_run curl \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/box/$_USERNAME/$_BOX_NAME/versions" \
      --data '{ "version": { "version": "'"$1"'" } }'
  )

  echo "$_RESPONSE" | _assert_request_success
}

_create_provider_for_box_version() {
  local _RESPONSE

  echo "creating provider $_PROVIDER_NAME for version $_VERSION"
  _RESPONSE=$(
    _safely_run curl \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/box/$_USERNAME/$_BOX_NAME/version/$_VERSION/providers" \
      --data '{ "provider": { "name": "'"$_PROVIDER_NAME"'" } }'
  )

  echo "$_RESPONSE" | _assert_request_success
}

_fetch_version_upload_url() {
  local _RESPONSE

  echo "fetching $_VERSION upload URL"
  _RESPONSE=$(
    _safely_run curl \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/box/$_USERNAME/$_BOX_NAME/versions" \
      --data '{ "version": { "version": "'"$_VERSION"'" } }'
  )

  _UPLOAD_URL=$(echo "$_RESPONSE" | _assert_request_success | _get_json_field "upload_path")
}

_release_box_version() {
  local _HOSTED_TOCKEN
  _HOSTED_TOCKEN=$(_safely_run curl -X PUT --upload-file "$_BOX_NAME".box "$_UPLOAD_URL")
  _PREVIOUSLY_RETRIEVED_TOKEN=$(echo "$_UPLOAD_URL" | sed -E 's/.*\/(.*)"/\1/')
  echo $"$_HOSTED_TOCKEN"
  echo $"$_PREVIOUSLY_RETRIEVED_TOKEN"

  if [ "$DRY_RUN" == "false" ] && [ "$_HOSTED_TOCKEN" == "$_PREVIOUSLY_RETRIEVED_TOKEN" ]; then
    echo "FATAL: Could not get the version upload link for some reason. Try uploadining online"
    exit 1
  fi
}

###############################################################################
# Main
###############################################################################

_main() {
  if [[ "${1:-}" =~ ^-h|--help$ ]]; then
    _print_help
  else

    _create_box_version_url "1.0.0"
    # _create_provider_for_box_version
    # _fetch_version_upload_url
    # _release_box_version
  fi
  # else
  #   case $1 in
  #     create)
  #       shift
  #       _package_box
  #       _create_box_url
  #       _read_create_args "$@"
  #       _create_box_version_url "1.0.0"
  #       ;;
  #     upgrage)
  #       shift
  #       _repackage_box
  #       _get_current_version
  #       _read_upgrade_args "$@"
  #       _create_box_version_url "$_VERSION"
  #       ;;
  #     revert)
  #       shift
  #       _read_revert_args "$@"
  #       _revert_box_version "$_VERSION"
  #       exit 0
  #       ;;
  #     *)
  #       echo "Unknown command recieved"
  #       _print_help
  #       exit 1
  #       ;;
  #   esac
  #   _create_provider_for_box_version
  #   _fetch_version_upload_url
  #   _release_box_version
  # fi
}

_main "$@"
