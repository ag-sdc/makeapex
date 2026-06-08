#!/bin/bash
# shellcheck disable=SC1091,SC2154,SC2034,SC1090
#
#   package_function_variable.sh - Check variables inside the package function.
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

[[ -n "$LIBMAKEAPEX_LINT_APEXBUILD_PACKAGE_FUNCTION_VARIABLE_SH" ]] && return
LIBMAKEAPEX_LINT_APEXBUILD_PACKAGE_FUNCTION_VARIABLE_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/util/message.sh"
source "$MAKEAPEX_LIBRARY/util/apexbuild.sh"
source "$MAKEAPEX_LIBRARY/util/schema.sh"
source "$MAKEAPEX_LIBRARY/util/util.sh"


lint_apexbuild_functions+=('lint_package_function_variable')


lint_package_function_variable() {
	local i a pkg ret=0

	# package function variables
	# shellcheck disable=SC2068
	for pkg in "${pkgname[@]}"; do
		# shellcheck disable=SC2068
		for a in "${arch[@]}"; do
			[[ $a == "any" ]] && continue

			# shellcheck disable=SC2068
			for i in "${apexbuild_schema_arrays[@]}" "${apexbuild_schema_strings[@]}"; do
				# shellcheck disable=SC2068
				in_array "$i" "${apexbuild_schema_package_overrides[@]}" && continue
				if exists_function_variable "package_$pkg" "${i}_${a}"; then
					error "$(gettext "%s can not be set inside a package function")" "${i}_${a}"
					ret=1
				fi
			done
		done

		# shellcheck disable=SC2068
		for i in "${apexbuild_schema_arrays[@]}" "${apexbuild_schema_strings[@]}"; do
			# shellcheck disable=SC2068
			in_array "$i" "${apexbuild_schema_package_overrides[@]}" && continue
			if exists_function_variable "package_$pkg" "$i"; then
				error "$(gettext "%s can not be set inside a package function")" "$i"
				ret=1
			fi
		done
	done

	return $ret
}
