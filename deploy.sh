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
_BOX_NAME="next_level_box"
_PROVIDER_NAME="virtualbox"
_VERSION="0.0.0"
_CURRENT_VERSION=""
_IS_NEW_BOX="false"
: "${ACCESS_TOKEN:?is not set}"
: "${DRY_RUN:?is not set}"
_ACCESS_TOKEN=$ACCESS_TOKEN
_DRY_RUN=$DRY_RUN

###############################################################################
# Help
###############################################################################

_print_help() {
  cat << HEREDOC
    ____   __  ___ _____    ____ _   __ ______ ______ ____   ____   ____
   / __ \ /  |/  // ___/   /  _// | / //_  __// ____// __ \ / __ \ / __ \
  / /_/ // /|_/ / \__ \    / / /  |/ /  / /  / __/  / /_/ // / / // /_/ /
 / ____// /  / / ___/ /  _/ / / /|  /  / /  / /___ / _, _// /_/ // ____/
/_/    /_/  /_/ /____/  /___//_/ |_/  /_/  /_____//_/ |_| \____//_/

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

_read_args_and_bump_verion() {
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

_check_for_box_existance() {
  local _CONTENT
  _CONTENT=$(vagrant box list | grep "$_BOX_NAME" || :)
  if [ -z "$_CONTENT" ]; then _IS_NEW_BOX="true"; else _IS_NEW_BOX="false"; fi
}

_get_current_version() {
  _CURRENT_VERSION=$(vagrant box list | grep "$_BOX_NAME" || : | sed -E 's/.*\(virtualbox, (.*)\)/\1/')
  echo "$_CURRENT_VERSION"
  if [ -z "$_CURRENT_VERSION" ]; then _CURRENT_VERSION="0.0.0"; fi
}

_safely_run() {
  _COMMAND=""
  if [[ "$_DRY_RUN" != "false" ]]; then
    printf -v _COMMAND "%q " "$@"
    echo "DRYRUN: Not executing $_COMMAND" >&2
  else
    "$@"
  fi
}

_repackage_box() {
  _BOX_PATH=$(_safely_run vagrant box repackage "$_BOX_NAME" "$_PROVIDER_NAME" "$_VERSION")

  if [ "$_DRY_RUN" == "false" ] && [ "$_BOX_PATH" == "" ]; then
    vagrant box list
    echo "FATAL: Could not repackage box. Make sure $_BOX_NAME is in this list otherwise package new"
    exit 1
  fi
}

_package_box() {
  _BOX_PATH=$(_safely_run vagrant package --output "$_BOX_NAME.box")

  if [ "$_DRY_RUN" == "false" ] && [ ! -f "./$_BOX_NAME.box" ]; then
    echo "FATAL: Could not package box. Make sure the VM you want to package is running in $_PROVIDER_NAME"
    exit 1
  fi
}

_get_upload_link() {
  # shellcheck disable=2016
  _UPLOAD_LINK=$(_safely_run curl "https://vagrantcloud.com/api/v1/box/$_USERNAME/$_BOX_NAME/version/$_VERSION/provider/$_PROVIDER_NAME/upload?access_token=$_ACCESS_TOKEN" | awk /upload_path/'{print $2}')

  if [ "$_DRY_RUN" == "false" ] && [ "$_UPLOAD_LINK" == "" ]; then
    echo "FATAL: Could not get the version upload link for some reason. Try uploadining online"
    exit 1
  fi
}

_upload_box() {
  _safely_run curl -X PUT --upload-file "$_BOX_NAME".box "$_UPLOAD_LINK"
  _PREVIOUSLY_RETRIEVED_TOKEN=$(echo "$_UPLOAD_LINK" | sed -E 's/.*\/(.*)"/\1/')

  if [ "$_DRY_RUN" == "false" ] && [ "$_HOSTED_TOCKEN" == "$_PREVIOUSLY_RETRIEVED_TOKEN" ]; then
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
    _check_for_box_existance
    _get_current_version
    if [ "$_IS_NEW_BOX" == "true" ]; then
      _package_box
    else
      _repackage_box
    fi
    _read_args_and_bump_verion "$@"
    _get_upload_link
    _upload_box
  fi
}

_main "$@"
