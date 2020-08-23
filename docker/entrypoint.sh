#!/bin/sh

set -eu

# setup
nimble c -d:release src/setup_nimforum.nim
./src/setup_nimforum --dev

# build frontend
nimble c -r src/buildcss
nimble js -d:release src/frontend/forum.nim
mkdir -p public/js
cp src/frontend/forum.js public/js/forum.js

# build backend
nimble c src/forum.nim
./src/forum
