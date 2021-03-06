#!/usr/bin/env bash

# Bash Strict Mode
set -o nounset
set -o errexit
set -o pipefail
set -o errtrace
IFS=$'\n\t'
trap 'echo "Aborting due to errexit on line $LINENO. Exit code: $?" >&2' ERR

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
  ${_ME} command [options]
  ${_ME} -h | --help
Commands:
  ${_ME} create
  ${_ME} upgrade [[--major/-ma] || [--minor/-mi] || [--patch/-p]]
  ${_ME} revert [[--latest/-l][--version/-v <semver>]]
Options:
  -h --help  Show this screen.
HEREDOC
}

###############################################################################
# Script Functions
###############################################################################

_read_create_args() {
  while [[ $# -gt 0 ]]; do
    _KEY="$1"
    case $_KEY in
      *)
        echo "Unknown argument recieved"
        _print_help
        exit 1
        shift
        ;;
    esac
  done
}

_read_upgrade_args() {
  while [[ $# -gt 0 ]]; do
    _KEY="$1"
    case $_KEY in
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
    echo "could not bump version"
    _print_help
    exit 1
  fi
}

_read_revert_args() {
  while [[ $# -gt 0 ]]; do
    _KEY="$1"
    case $_KEY in
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

_assert_request_success() {
  local _SUCCESS
  local _ERROR
  local _REQUEST_NAME
  _SUCCESS=$(echo "$1" | jq ."success")
  _REQUEST_NAME=$(echo "$2" | awk -F_ '{for (i=1; i<=NF; ++i) { $i=toupper(substr($i,1,1)) tolower(substr($i,2)); } print }')
  if [ "$_SUCCESS" == "false" ]; then
    _ERROR=$(echo "$1" | jq ."errors")
    echo "FATAL:$_REQUEST_NAME failed. Errors:$_ERROR"
    exit 42
  fi
}

_get_current_version() {
  _CURRENT_VERSION=$(vagrant box list | grep "$_BOX_NAME" || : | sed -E 's/.*\(virtualbox, (.*)\)/\1/')
}

_safely_run() {
  local _COMMAND=""
  if [[ "$DRY_RUN" != "false" ]]; then
    printf -v _COMMAND "%q " "$@"
    echo "DRYRUN: Not executing $_COMMAND" >&2
  else
    "$@"
  fi
}

_box_file() {
  echo "${_BOX_NAME}_${_VERSION}.box"
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
  local _RESPONSE

  echo "creating box: $_BOX_NAME in Vagrant Cloud"
  _RESPONSE=$(
    _safely_run curl \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/boxes" \
      --data '{ "box": { "username": "'"$_USERNAME"'", "name": "'"$_BOX_NAME"'" } }'
  )

  _assert_request_success "$_RESPONSE" "${FUNCNAME[0]}"
}

_create_box_version_url() {
  local _RESPONSE

  echo "creating version url for $_VERSION"
  _RESPONSE=$(
    _safely_run curl \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/box/$_USERNAME/$_BOX_NAME/versions" \
      --data '{ "version": { "version": "'"$_VERSION"'" } }'
  )

  _assert_request_success "$_RESPONSE" "${FUNCNAME[0]}"
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

  _assert_request_success "$_RESPONSE" "${FUNCNAME[0]}"
}

_fetch_version_upload_url() {
  local _RESPONSE

  echo "fetching version $_VERSION upload URL"
  _RESPONSE=$(
    _safely_run curl \
      --header "Content-Type: application/json" \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/box/$_USERNAME/$_BOX_NAME/version/$_VERSION/provider/$_PROVIDER_NAME/upload" \
      --data '{ "version": { "version": "'"$_VERSION"'" } }'
  )

  _assert_request_success "$_RESPONSE" "${FUNCNAME[0]}"
  _UPLOAD_URL=$(echo "$_RESPONSE" | jq ."upload_path")
}

_upload_box() {
  local _RESPONSE

  echo "fetching version $_VERSION upload URL"
  _RESPONSE=$(
    _safely_run curl \
      "$_UPLOAD_URL" \
      --request PUT \
      --upload-file "dry_run.box"
  )

  _assert_request_success "$_RESPONSE" "${FUNCNAME[0]}"
}

_release_version() {
  local _RESPONSE

  echo "fetching version $_VERSION upload URL"
  _RESPONSE=$(
    _safely_run curl \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      "https://app.vagrantup.com/api/v1/box/$_USERNAME/$_BOX_NAME/version/$_VERSION/release" \
      --request PUT
  )

  _assert_request_success "$_RESPONSE" "${FUNCNAME[0]}"
}

###############################################################################
# Main
###############################################################################

_main() {
  if [[ "${1:-}" =~ ^-h|--help$ ]]; then
    _print_help
  else
    : "${1:?"FATAL: command is not set $(echo -e "\n$(_print_help)")"}"
    _CMD="$1"
    shift
    case "$_CMD" in
      create)
        _read_create_args "$@"
        # _package_box
        # _create_box_url
        _VERSION=1.0.0
        # _create_box_version_url
        ;;
      upgrage)
        _read_upgrade_args "$@"
        _repackage_box
        _get_current_version
        _create_box_version_url
        ;;
      revert)
        _read_revert_args "$@"
        _revert_box_version "$_VERSION"
        exit 0
        ;;
      *)
        echo "Unknown command recieved"
        _print_help
        exit 99
        ;;
    esac
    _create_provider_for_box_version
    _fetch_version_upload_url
    _upload_box
    _release_version
  fi
}

_main "$@"
