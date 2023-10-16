# Package
version       = "2.2.0"
author        = "Dominik Picheta"
description   = "The Nim forum"
license       = "MIT"

srcDir = "src"

bin = @["forum"]

skipExt = @["nim"]

# Dependencies

requires "nim >= 1.0.6"
requires "httpbeast >= 0.4.0"
requires "jester#405be2e"
requires "bcrypt#440c5676ff6"
requires "hmac#9c61ebe2fd134cf97"
requires "recaptcha#d06488e"
requires "sass#649e0701fa5c"

requires "karax#45bac6b"

requires "webdriver#c5e4182"

when NimMajor > 1:
  requires "db_connector >= 0.1.0"
  requires "smtp >= 0.1.0"

# Tasks

task backend, "Compiles and runs the forum backend":
  exec "nimble c --mm:refc src/forum.nim"
  exec "./src/forum"

task runbackend, "Runs the forum backend":
  exec "./src/forum"

task testbackend, "Runs the forum backend in test mode":
  exec "nimble c -r --mm:refc -d:skipRateLimitCheck src/forum.nim"

task frontend, "Builds the necessary JS frontend (with CSS)":
  exec "nimble c -r --mm:refc src/buildcss"
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
  exec "nimble c -y --mm:refc src/forum.nim"
  exec "nimble c -y -r -d:actionDelayMs=0 tests/browsertester"

task fasttest, "Runs tester without recompiling backend":
  exec "nimble c -r -d:actionDelayMs=0 tests/browsertester"
