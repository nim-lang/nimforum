import os, options, unittest
import webdriver
import macros

macro with*(obj: typed, code: untyped): untyped =
  ## Execute a set of statements with an object
  expectKind code, nnkStmtList
  result = code

  # Simply inject obj into call
  for i in 0 ..< result.len:
    if result[i].kind in {nnkCommand, nnkCall}:
      result[i].insert(1, obj)

template click*(session: Session, element: string, strategy=CssSelector) =
  let el = session.findElement(element, strategy)
  check el.isSome()
  el.get().click()

template sendKeys*(session: Session, element, keys: string) =
  let el = session.findElement(element)
  check el.isSome()
  el.get().sendKeys(keys)

template sendKeys*(session: Session, element: string, keys: varargs[Key]) =
  let el = session.findElement(element)
  check el.isSome()

  # focus
  el.get().click()
  for key in keys:
    session.press(key)

template ensureExists*(session: Session, element: string) =
  let el = session.findElement(element)
  check el.isSome()

template check*(session: Session, element: string, function: untyped) =
  let el = session.findElement(element)
  check function(el)

template check*(session: Session, element: string,
                strategy: LocationStrategy, function: untyped) =
  let el = session.findElement(element, strategy)
  check function(el)

template checkIsNone*(session: Session, element: string, strategy=CssSelector) =
  let el = session.findElement(element, strategy)
  check el.isNone()

template checkText*(session: Session, element, expectedValue: string) =
  let el = session.findElement(element)
  check el.isSome()
  check el.get().getText() == expectedValue

proc waitForLoad*(session: Session, timeout=20000) =
  var waitTime = 0
  sleep(2000)

  while true:
    let loading = session.findElement(".loading")
    if loading.isNone: return
    sleep(1000)
    waitTime += 1000

    if waitTime > timeout:
      doAssert false, "Wait for load time exceeded"

proc wait*(session: Session) =
  session.waitForLoad()

proc wait*(session: Session, msTimeout: int) =
  session.waitForLoad(msTimeout)

proc logout*(session: Session) =
  with session:
    wait(5000)
    click "#profile-btn"
    click "#profile-btn #logout-btn"
    wait(5000)

proc login*(session: Session, user, password: string) =
  with session:
    click "#login-btn"

    sendKeys "#login-form input[name='username']", user
    sendKeys "#login-form input[name='password']", password

    sendKeys "#login-form input[name='password']", Key.Enter

    wait(5000)
