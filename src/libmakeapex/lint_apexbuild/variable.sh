#!/bin/bash
# shellcheck disable=SC1091,SC2154,SC2034,SC1090
#
#   variable.sh - Check that variables are or are not arrays as appropriate
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

[[ -n "$LIBMAKEAPEX_LINT_APEXBUILD_VARIABLE_SH" ]] && return
LIBMAKEAPEX_LINT_APEXBUILD_VARIABLE_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/util/message.sh"
source "$MAKEAPEX_LIBRARY/util/apexbuild.sh"
source "$MAKEAPEX_LIBRARY/util/schema.sh"

lint_apexbuild_functions+=('lint_variable')
lint_apexbuild_functions+=('lint_array')

lint_variable() {
	local i a pkg out bad ret=0

	# global variables
	# shellcheck disable=SC2068
	for i in "${apexbuild_schema_arrays[@]}"; do
		if declare -p "$i" > /dev/null 2>&1; then
			if ! is_array "$i"; then
				error "$(gettext "%s should be an array")" "$i"
				ret=1
			fi
		fi
	done

	# shellcheck disable=SC2068
	for a in "${arch[@]}"; do
		[[ $a == "any" ]] && continue

		# shellcheck disable=SC2068
		for i in "${apexbuild_schema_arch_arrays[@]}"; do
			if declare -p "${i}_${a}" > /dev/null 2>&1; then
				if ! is_array "${i}"_"${a}"; then
					error "$(gettext "%s should be an array")" "${i}_${a}"
					ret=1
				fi
			fi
		done
	done

	# shellcheck disable=SC2068
	for i in "${apexbuild_schema_strings[@]}"; do
		if declare -p "$i" > /dev/null 2>&1; then
			if is_array "$i"; then
				error "$(gettext "%s should not be an array")" "$i"
				ret=1
			fi
		fi
	done

	# package function variables
	# shellcheck disable=SC2068
	for pkg in "${pkgname[@]}"; do
		# shellcheck disable=SC2068
		for i in "${apexbuild_schema_arrays[@]}"; do
			if extract_function_variable "package_$pkg" "$i" 0 out; then
				error "$(gettext "%s should be an array")" "$i"
				ret=1
			fi
		done

		# shellcheck disable=SC2068
		for a in "${arch[@]}"; do
			[[ $a == "any" ]] && continue

			# shellcheck disable=SC2068
			for i in "${apexbuild_schema_arch_arrays[@]}"; do
				if extract_function_variable "package_$pkg" "${i}_${a}" 0 out; then
					error "$(gettext "%s should be an array")" "${i}_${a}"
					ret=1
				fi
			done
		done

		# shellcheck disable=SC2068
		for i in "${apexbuild_schema_strings[@]}"; do
			if extract_function_variable "package_$pkg" "$i" 1 out; then
				error "$(gettext "%s should not be an array")" "$i"
				ret=1
			fi
		done
	done

	return $ret
}

lint_array() {
	local i var ret=0

	# shellcheck disable=SC2068
	for i in "${apexbuild_schema_arrays[@]}"; do
		local l=()
		get_apexbuild_all_split_attributes "$i" l

		for var in "${l[@]}"; do
			if [[ -z $var ]]; then
				error "$(gettext "%s does not allow empty values.")" "$i"
				ret=1
			fi
		done
	done

	return $ret
}
