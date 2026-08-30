#!/usr/bin/env sh
set -e

has_command() {
	command -v "$1" >/dev/null 2>&1
	return $?
}
use_dc() {
	bn="$(basename "${DC}")"

	if [ "$bn" = "dmd" ] || [ "$bn" = "ldmd2" ] || [ "$bn" = "ldmd" ] || [ "$bn" = "gdmd" ]; then
		export DMD="$DC"
		use_dmd
		return $?
	elif [ "$bn" = "gdc" ]; then
		use_gdc
		return $?
	elif [ "$bn" = "ldc2" ] || [ "$bn" = "ldc" ]; then
		use_ldc
		return $?
	else
		echo "Unsupported D compiler \`$DC\`."
		return 1
	fi
}
use_dmd() {
	[ -z "${DFLAGS+x}" ] && export DFLAGS="-O"
	"$DMD" $DFLAGS   -of"bin/mindybuild" -od"bin" -I"src"    -version="${version}"            $sourceFiles
	return $?
}
use_gdc() {
	[ -z "${DFLAGS+x}" ] && export DFLAGS="-O2"
	"$DC"  $DFLAGS  -o  "bin/mindybuild"          -I"src"   -fversion="${version}"            $sourceFiles
	return $?
}
use_ldc() {
	[ -z "${DFLAGS+x}" ] && export DFLAGS="-O2"
	"$DC"  $DFLAGS --of="bin/mindybuild"          -I"src" --d-version="${version}" -singleobj $sourceFiles
	return $?
}

mkdir -p bin

if [ -n "${UNITTEST+x}" ]; then
	version="MindybuildUnittestApp"
	export DFLAGS="$DFLAGS -unittest"
else
	version="MindybuildCommandLineApp"
fi

sourceFiles="\
	src/mindybuild/common.d \
	src/mindybuild/database.d \
	src/mindybuild/kapenparse.d \
	src/mindybuild/configure.d \
	src/mindybuild/make.d \
	src/mindybuild/cli.d"

if [ -n "${DC+x}" ]; then
	use_dc
	exit $?
elif [ -n "${DMD+x}" ]; then
	use_dmd
	return $?
elif has_command "ldc2"; then
	export DC="ldc2"
elif has_command "gdc"; then
	export DC="gdc"
elif has_command "dmd"; then
	export DC="dmd"
else
	echo "No suitable D compiler found."
	exit 1
fi

use_dc
exit $?
