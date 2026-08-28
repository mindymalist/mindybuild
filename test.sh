#!/usr/bin/env sh
set -ex
export UNITTEST=1
./build.sh
./bin/mindybuild
