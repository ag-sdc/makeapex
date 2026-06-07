#!/bin/bash
#
#   linkerconfig.sh - Generate Android linker.config.json and apex_manifest.json deps
#

[[ -n "$LIBMAKEAPEX_TIDY_LINKERCONFIG_SH" ]] && return
LIBMAKEAPEX_TIDY_LINKERCONFIG_SH=1

MAKEAPEX_LIBRARY=${MAKEAPEX_LIBRARY:-"$(dirname "$0")/libmakeapex"}

source "$MAKEAPEX_LIBRARY/util/message.sh"
source "$MAKEAPEX_LIBRARY/util/apexbuild.sh"

tidy_modify+=('tidy_linkerconfig')

tidy_linkerconfig() {
	msg2 "$(gettext "Generating APEX linker configuration and dependencies...")"

	local req_libs=()
	local prov_libs=()

	local dummy_prefix=""
	if [[ " ${arch[*]} " =~ " x86_64 " ]] || [[ "$CARCH" == "x86_64" ]]; then
		local lvl=${_microarch_level:-2}
		if [[ "$lvl" -gt 1 ]]; then
			dummy_prefix="-x86_64-v${lvl}"
		fi
	elif [[ " ${arch[*]} " =~ " aarch64 " ]] || [[ "$CARCH" == "aarch64" ]]; then
		local lvl=${_microarch_level:-8.2}
		if awk -v a="$lvl" -v b="8.0" 'BEGIN { exit !(a > b) }'; then
			dummy_prefix="-aarch64-v${lvl//./_}"
		fi
	fi

	# 1. Generate libdummy files from provides=()
	for p in "${provides[@]}"; do
		if [[ "$p" == _* ]]; then
			local dummy_name="libdummy${dummy_prefix}${p//_/-}.so"
			msg2 "$(gettext "Generating virtual dependency library: $dummy_name")"
			mkdir -p "$pkgdir/vendor/lib"
			# Echo an empty C file and compile it as a shared library
			echo 'void dummy(){}' | gcc -shared -xc - -o "$pkgdir/vendor/lib/$dummy_name"
			prov_libs+=("$dummy_name")
		fi
	done

	# 2. Introspect all ELF binaries in the pkgdir
	while IFS= read -rd '' binary ; do
		# check if it's an ELF file
		if LC_ALL=C readelf -h "$binary" 2>/dev/null | grep -q 'ELF'; then
			# Extract SONAME (what it provides)
			local soname
			soname=$(LC_ALL=C readelf -d "$binary" 2>/dev/null | grep 'SONAME' | sed -E 's/.*\[([^]]+)\].*/\1/')
			if [[ -n "$soname" ]]; then
				prov_libs+=("$soname")
			fi

			# Extract NEEDED (what it requires)
			while IFS= read -r n; do
				if [[ -n "$n" ]]; then
					req_libs+=("$n")
				fi
			done < <(LC_ALL=C readelf -d "$binary" 2>/dev/null | grep 'NEEDED' | sed -E 's/.*\[([^]]+)\].*/\1/')
		fi
	done < <(find "$pkgdir" -type f -perm -u+w -print0 2>/dev/null)

	# 3. Add explicit depends and provides from APEXBUILD
	for d in "${depends[@]}"; do
		if [[ "$d" == *.so ]]; then
			req_libs+=("$d")
		elif [[ "$d" == _* ]]; then
			req_libs+=("libdummy${dummy_prefix}${d//_/-}.so")
		fi
	done

	for p in "${provides[@]}"; do
		if [[ "$p" == *.so ]]; then
			prov_libs+=("$p")
		elif [[ "$p" == _* ]]; then
			prov_libs+=("libdummy${dummy_prefix}${p//_/-}.so")
		fi
	done

	# 4. Filter and deduplicate
	local unique_req=()
	local unique_prov=()

	# deduplicate prov_libs
	if [ ${#prov_libs[@]} -gt 0 ]; then
		while IFS= read -r line; do
			unique_prov+=("$line")
		done < <(printf "%s\n" "${prov_libs[@]}" | sort -u)
	fi

	# deduplicate req_libs and remove any that are in unique_prov
	if [ ${#req_libs[@]} -gt 0 ]; then
		while IFS= read -r line; do
			local found=0
			for p in "${unique_prov[@]}"; do
				if [[ "$line" == "$p" ]]; then
					found=1
					break
				fi
			done
			if [[ $found -eq 0 ]]; then
				unique_req+=("$line")
			fi
		done < <(printf "%s\n" "${req_libs[@]}" | sort -u)
	fi

	# 5. Write linker.config.json
	mkdir -p "$pkgdir/etc"
	local linker_config="$pkgdir/etc/linker.config.json"
	
	echo "{" > "$linker_config"
	
	echo "  \"provideLibs\": [" >> "$linker_config"
	local i=0
	for p in "${unique_prov[@]}"; do
		if [[ $i -gt 0 ]]; then echo "    ," >> "$linker_config"; else echo "    " >> "$linker_config"; fi
		echo -n "    \"$p\"" >> "$linker_config"
		i=$((i+1))
	done
	if [[ $i -gt 0 ]]; then echo "" >> "$linker_config"; fi
	echo "  ]," >> "$linker_config"
	
	echo "  \"requireLibs\": [" >> "$linker_config"
	i=0
	for r in "${unique_req[@]}"; do
		if [[ $i -gt 0 ]]; then echo "    ," >> "$linker_config"; else echo "    " >> "$linker_config"; fi
		echo -n "    \"$r\"" >> "$linker_config"
		i=$((i+1))
	done
	if [[ $i -gt 0 ]]; then echo "" >> "$linker_config"; fi
	echo "  ]," >> "$linker_config"
	
	echo "  \"visible\": true" >> "$linker_config"
	echo "}" >> "$linker_config"

	# 6. Save the unique_req and unique_prov for the apex_manifest.json generator
	rm -f "$pkgdirbase/.provideNativeLibs" "$pkgdirbase/.requireNativeLibs"
	if [ ${#unique_prov[@]} -gt 0 ]; then
		printf "%s\n" "${unique_prov[@]}" > "$pkgdirbase/.provideNativeLibs"
	fi
	if [ ${#unique_req[@]} -gt 0 ]; then
		printf "%s\n" "${unique_req[@]}" > "$pkgdirbase/.requireNativeLibs"
	fi
}
