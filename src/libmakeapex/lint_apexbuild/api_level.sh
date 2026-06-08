#!/bin/bash
#
#   api_level.sh - Check the 'api_level' variable conforms to requirements.
#

[[ -n "$LIBMAKEAPEX_LINT_APEXBUILD_API_LEVEL_SH" ]] && return
LIBMAKEAPEX_LINT_APEXBUILD_API_LEVEL_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/util/message.sh"


lint_apexbuild_functions+=('lint_api_level')


check_api_level() {
	local level=$1

	if [[ -z $level ]]; then
		return 0
	fi

	if [[ $level != *([[:digit:]]) ]]; then
		error "$(gettext "api_level must be an integer between 29 and 37.")"
		return 1
	fi

	if (( level < 29 || level > 37 )); then
		error "$(gettext "api_level must be an integer between 29 and 37.")"
		return 1
	fi
}

lint_api_level() {
	check_api_level "$api_level"
}
