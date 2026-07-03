#!/bin/sh

set -eu

git submodule update --init --recursive

# setup
nim c -d:release src/setup_nimforum.nim
./src/setup_nimforum --dev

# build frontend
nim c -r src/buildcss
nim js -d:release src/frontend/forum.nim
mkdir -p public/js
cp src/frontend/forum.js public/js/forum.js

# build backend
nim c -mm:refc src/forum.nim
./src/forum
