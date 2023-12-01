#!/bin/bash

# shellcheck disable=SC2091
if [ -z "${GITHUB_ENV}" ] && ! $(return 0 2>/dev/null); then
  echo "This script must be run by sourcing it:"
  echo "source $0 $*"
  exit 1
fi

# Find the parent directory in a way compatible with bash and zsh
tools_path="${BASH_SOURCE%/*}"
[ -z "$tools_path" ] && tools_path="$(dirname "$0")"

export BUILDENV_RELEASE=TRUE

# shellcheck disable=SC1091
source "${tools_path}/macos_buildenv.sh" "$@"
