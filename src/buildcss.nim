import os, strutils

import sass

import utils

proc buildCSS*(config: Config) =
  let publicLoc = "public"
  var includePaths: seq[string] = @[]
  # Check for a styles override.
  var hostname = config.hostname
  if not existsDir(hostname):
    hostname = "localhost.local"

  let dir = getCurrentDir() / hostname / "public"
  includePaths.add(dir / "css")
  createDir(publicLoc / "images")
  let logo = publicLoc / "images" / "logo.png"
  removeFile(logo)
  createSymlink(
    dir / "images" / "logo.png",
    logo
  )

  let cssLoc = publicLoc / "css"
  sass.compileFile(
    cssLoc / "nimforum.scss",
    cssLoc / "nimforum.css",
    includePaths=includePaths
  )

when isMainModule:
  let config = loadConfig()
  buildCSS(config)
  echo("CSS Built successfully")