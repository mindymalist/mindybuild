#!/usr/bin/env sh
set -e

has_command() {
	command -v "$1" >/dev/null 2>&1
	return $?
}
use_dc() {
	if [ "$DC" = "dmd" ] || [ "$DC" = "ldmd2" ] || [ "$DC" = "ldmd" ] || [ "$DC" = "gdmd" ]; then
		export DMD="$DC"
		use_dmd
		return $?
	elif [ "$DC" = "gdc" ]; then
		use_gdc
		return $?
	elif [ "$DC" = "ldc2" ] || [ "$DC" = "ldc" ]; then
		use_ldc
		return $?
	else
		echo "Unsupported D compiler \`$DC\`."
		return 1
	fi
}
use_dmd() {
	$DMD $DFLAGS -g -O    -of"bin/mindybuild" -od"bin" -I"src"    -version="MindybuildCommandLineApp" $sourceFiles
	return $?
}
use_gdc() {
	$DC  $DFLAGS -g -O2  -o  "bin/mindybuild"          -I"src"   -fversion="MindybuildCommandLineApp" $sourceFiles
	return $?
}
use_ldc() {
	$DC  $DFLAGS -g -O2 --of="bin/mindybuild"          -I"src" --d-version="MindybuildCommandLineApp" $sourceFiles
	return $?
}

mkdir -p bin

sourceFiles="\
	src/mindybuild/common.d \
	src/mindybuild/kapenparse.d \
	src/mindybuild/configure.d \
	src/mindybuild/make.d \
	src/mindybuild/cli.d"

if [ -n "${DC+x}" ]; then
	use_dc
	return $?
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
	return 1
fi

use_dc
return $?
