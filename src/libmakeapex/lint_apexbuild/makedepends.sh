#!/bin/bash
# shellcheck disable=SC1091,SC2154,SC2034,SC1090
#
#   makedepends.sh - Check the 'makedepends' array conforms to requirements.
#
#   Copyright (c) 2014-2025 Pacman Development Team <pacman-dev@lists.archlinux.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

[[ -n "$LIBMAKEAPEX_LINT_APEXBUILD_MAKEDEPENDS_SH" ]] && return
LIBMAKEAPEX_LINT_APEXBUILD_MAKEDEPENDS_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/lint_apexbuild/fullpkgver.sh"
source "$MAKEAPEX_LIBRARY/lint_apexbuild/pkgname.sh"
source "$MAKEAPEX_LIBRARY/util/message.sh"
source "$MAKEAPEX_LIBRARY/util/apexbuild.sh"


lint_apexbuild_functions+=('lint_makedepends')


lint_makedepends() {
	local makedepends_list makedepend name ver ret=0

	get_apexbuild_all_split_attributes makedepends makedepends_list

	# this function requires extglob - save current status to restore later
	local shellopts; shellopts=$(shopt -p extglob)
	shopt -s extglob

	for makedepend in "${makedepends_list[@]}"; do
		name=${makedepend%%@(<|>|=|>=|<=)*}
		lint_one_pkgname makedepends "$name" || ret=1
		if [[ $name != "$makedepend" ]]; then
			ver=${makedepend##"$name"@(<|>|=|>=|<=)}
			check_fullpkgver "$ver" makedepends || ret=1
		fi
	done

	eval "$shellopts"

	return $ret
}
