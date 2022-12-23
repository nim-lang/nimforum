import std/[options, osproc, streams, threadpool, os, strformat, httpclient, json]

import webdriver

proc runProcess(cmd: string) =
  let p = startProcess(
    cmd,
    options={
      poStdErrToStdOut,
      poEvalCommand
    }
  )

  let o = p.outputStream
  while p.running and (not o.atEnd):
    echo cmd.substr(0, 10), ": ", o.readLine()

  p.close()

const backend = "forum"
const port = 5000
const baseUrl = "http://localhost:" & $port & "/"
template withBackend(body: untyped): untyped =
  ## Starts a new backend instance.

  spawn runProcess("nimble -y testbackend")
  defer:
    discard execCmd("killall " & backend)

  echo("Waiting for server...")
  var success = false
  for i in 0..5:
    sleep(5000)
    try:
      let client = newHttpClient()
      doAssert client.getContent(baseUrl).len > 0
      success = true
      break
    except:
      echo("Failed to getContent")

  doAssert success

  body

import browsertests/[scenario1, threads, issue181, categories]

proc main() =
  # Kill any already running instances
  discard execCmd("killall chromedriver")
  spawn runProcess("chromedriver --port=4444 --log-level=DEBUG")
  defer:
    discard execCmd("killall chromedriver")

  # Create a fresh DB for the tester.
  doAssert(execCmd("nimble testdb") == QuitSuccess)

  doAssert(execCmd("nimble -y frontend") == QuitSuccess)
  echo("Waiting for chromedriver to startup...")
  sleep(5000)

  try:
    let driver = newWebDriver()
    let session = driver.createSession(%*{"capabilities": {"alwaysMatch": {"browserName": "chrome", "goog:chromeOptions": {"args": ["--headless", "--no-sandbox", "--disable-dev-shm-usage", "disable-infobars", "--disable-extension"]}}}})

    withBackend:
      scenario1.test(session, baseUrl)
      threads.test(session, baseUrl)
      categories.test(session, baseUrl)
      issue181.test(session, baseUrl)

    session.close()
  except:
    sleep(10000) # See if we can grab any more output.
    raise

when isMainModule:
  main()
