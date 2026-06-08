#!/bin/bash
# shellcheck disable=SC1091,SC2154,SC2034,SC1090
#
#   buildenv.sh - functions for altering the build environment before
#   compilation
#
#   Copyright (c) 2015-2025 Pacman Development Team <pacman-dev@lists.archlinux.org>
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

[[ -n "$LIBMAKEAPEX_BUILDENV_SH" ]] && return
LIBMAKEAPEX_BUILDENV_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

declare -a buildenv_functions build_options
buildenv_vars=('CPPFLAGS' 'CFLAGS' 'CXXFLAGS' 'LDFLAGS')

for lib in "$MAKEAPEX_LIBRARY/buildenv/"*.sh; do
	source "$lib"
done

readonly -a buildenv_functions buildenv_vars build_options

prepare_buildenv() {
	local ret=0
	# ensure this function runs first
	buildenv_buildflags

	# shellcheck disable=SC2068
	for func in "${buildenv_functions[@]}"; do
		$func || ret=1
	done

	# ensure all necessary build variables are exported
	# shellcheck disable=SC2068
	export "${buildenv_vars[@]}" CHOST MAKEFLAGS
	return $ret
}
