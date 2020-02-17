# Package
version       = "2.0.2"
author        = "Dominik Picheta"
description   = "The Nim forum"
license       = "MIT"

srcDir = "src"

bin = @["forum"]

skipExt = @["nim"]

# Dependencies

requires "nim >= 1.0.6"
requires "jester#d8a03aa"
requires "bcrypt#head"
requires "hmac#9c61ebe2fd134cf97"
requires "recaptcha#d06488e"
requires "sass#649e0701fa5c"

requires "karax#f6bda9a"

requires "webdriver#c2fee57"

# Tasks

task backend, "Compiles and runs the forum backend":
  exec "nimble c src/forum.nim"
  exec "./src/forum"

task runbackend, "Runs the forum backend":
  exec "./src/forum"

task frontend, "Builds the necessary JS frontend (with CSS)":
  exec "nimble c -r src/buildcss"
  exec "nimble js -d:release src/frontend/forum.nim"
  mkDir "public/js"
  cpFile "src/frontend/forum.js", "public/js/forum.js"

task minify, "Minifies the JS using Google's closure compiler":
  exec "closure-compiler public/js/forum.js --js_output_file public/js/forum.js.opt"

task testdb, "Creates a test DB (with admin account!)":
  exec "nimble c src/setup_nimforum"
  exec "./src/setup_nimforum --test"

task devdb, "Creates a test DB (with admin account!)":
  exec "nimble c src/setup_nimforum"
  exec "./src/setup_nimforum --dev"

task blankdb, "Creates a blank DB":
  exec "nimble c src/setup_nimforum"
  exec "./src/setup_nimforum --blank"

task test, "Runs tester":
  exec "nimble c -y src/forum.nim"
  exec "nimble c -y -r -d:actionDelayMs=0 tests/browsertester"

task fasttest, "Runs tester without recompiling backend":
  exec "nimble c -r -d:actionDelayMs=0 tests/browsertester"
