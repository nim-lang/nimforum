import sass, os

when isMainModule:
  compileFile(
    getCurrentDir() / "public" / "css" / "nimforum.scss",
    getCurrentDir() / "public" / "css" / "nimforum.css"
  )

  echo("Compiled CSS")