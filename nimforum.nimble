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

# Tasks

task backend, "Runs the forum backend":
  exec "nimble c src/forum.nim"
  exec "./src/forum"

task frontend, "Builds the necessary JS frontend":
  exec "nimble js src/frontend/forum.nim"
  mkDir "public/js"
  cpFile "src/frontend/nimcache/forum.js", "public/js/forum.js"