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
_BOX_NAME="pls"
_PROVIDER_NAME="virtualbox"
_VERSION=""
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

_get_current_version() {
  _CURRENT_VERSION=$(vagrant box list | grep $_BOX_NAME | sed -E 's/.*\(virtualbox, (.*)\)/\1/')
}

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

_safely_run() {
  _COMMAND=""
  if [[ "$_DRY_RUN" != "false" ]]; then
    printf -v _COMMAND "%q " "$@"
    echo "DRYRUN: Not executing $_COMMAND" >&2
  else
    "$@"
  fi
}

_get_upload_link() {
  _UPLOAD_LINK=$(_safely_run curl "https://vagrantcloud.com/api/v1/box/$_USERNAME/$_BOX_NAME/version/$_VERSION/provider/$_PROVIDER_NAME/upload?access_token=$_ACCESS_TOKEN" | _safely_run awk /upload_path/'{print $2}')
}

###############################################################################
# Main
###############################################################################

_main() {
  if [[ "${1:-}" =~ ^-h|--help$ ]]; then
    _print_help
  else
    _get_current_version
    _read_args_and_bump_verion "$@"
    _get_upload_link
  fi
}

_main "$@"
