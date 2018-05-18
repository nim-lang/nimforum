# Package
version       = "0.1.0"
author        = "Dominik Picheta"
description   = "The Nim forum"
license       = "MIT"

srcDir = "src"

bin = @["forum"]

skipExt = @["nim"]

# Dependencies

requires "nim >= 0.14.0"
requires "jester#head"
requires "bcrypt#head"
requires "recaptcha >= 1.0.0"
requires "sass"

requires "karax"

requires "webdriver"

# Tasks

task backend, "Compiles and runs the forum backend":
  exec "nimble c src/forum.nim"
  exec "./src/forum"

task runbackend, "Runs the forum backend":
  exec "./src/forum"

task frontend, "Builds the necessary JS frontend":
  exec "nimble js src/frontend/forum.nim"
  mkDir "public/js"
  cpFile "src/frontend/nimcache/forum.js", "public/js/forum.js"

task testdb, "Creates a test DB":
  exec "nimble c src/setup_nimforum"
  exec "./src/setup_nimforum --test"

task devdb, "Creates a test DB":
  exec "nimble c src/setup_nimforum"
  exec "./src/setup_nimforum --dev"

task test, "Runs tester":
  exec "nimble c src/forum.nim"
  exec "nimble c -r tests/browsertester"

task fasttest, "Runs tester without recompiling backend":
  exec "nimble c -r tests/browsertester"