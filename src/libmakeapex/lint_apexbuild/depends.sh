#!/bin/bash
# shellcheck disable=SC1091,SC2154,SC2034,SC1090
#
#   depends.sh - Check the 'depends' array conforms to requirements.
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

[[ -n "$LIBMAKEAPEX_LINT_APEXBUILD_DEPENDS_SH" ]] && return
LIBMAKEAPEX_LINT_APEXBUILD_DEPENDS_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/lint_apexbuild/fullpkgver.sh"
source "$MAKEAPEX_LIBRARY/lint_apexbuild/pkgname.sh"
source "$MAKEAPEX_LIBRARY/util/message.sh"
source "$MAKEAPEX_LIBRARY/util/apexbuild.sh"


lint_apexbuild_functions+=('lint_depends')


lint_depends() {
	local depends_list depend name ver ret=0

	get_apexbuild_all_split_attributes depends depends_list

	# this function requires extglob - save current status to restore later
	local shellopts; shellopts=$(shopt -p extglob)
	shopt -s extglob

	for depend in "${depends_list[@]}"; do
		name=${depend%%@(<|>|=|>=|<=)*}
		lint_one_pkgname depends "$name" || ret=1
		if [[ $name != "$depend" ]]; then
			ver=${depend##"$name"@(<|>|=|>=|<=)}
			# Don't validate empty version because of https://bugs.archlinux.org/task/58776
			if [[ -n $ver ]]; then
				check_fullpkgver "$ver" depends || ret=1
			fi
		fi
	done

	eval "$shellopts"

	return $ret
}
