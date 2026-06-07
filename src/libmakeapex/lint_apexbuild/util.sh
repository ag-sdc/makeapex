#!/bin/bash
#
#   util.sh - utility functions for apexbuild linting.
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

[[ -n "$LIBMAKEAPEX_LINT_APEXBUILD_UTIL_SH" ]] && return
LIBMAKEAPEX_LINT_APEXBUILD_UTIL_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/util/message.sh"


check_files_exist() {
	local kind=$1 files=("${@:2}") file ret=0

	for file in "${files[@]}"; do
		if [[ $file && ! -f $file ]]; then
			error "$(gettext "%s file (%s) does not exist or is not a regular file.")" \
				"$kind" "$file"
			ret=1
		fi
	done

	return $ret
}
