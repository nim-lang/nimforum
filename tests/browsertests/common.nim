import os, options, unittest, strutils
import webdriver
import macros

const actionDelayMs {.intdefine.} = 0
## Inserts a delay in milliseconds between automated actions. Useful for debugging tests

macro with*(obj: typed, code: untyped): untyped =
  ## Execute a set of statements with an object
  expectKind code, nnkStmtList

  template checkCompiles(res, default) =
    when compiles(res):
      res
    else:
      default

  result = code.copy

  # Simply inject obj into call
  for i in 0 ..< result.len:
    if result[i].kind in {nnkCommand, nnkCall}:
      result[i].insert(1, obj)

  result = getAst(checkCompiles(result, code))

proc elementIsSome(element: Option[Element]): bool =
  return element.isSome

proc elementIsNone(element: Option[Element]): bool =
  return element.isNone

proc waitForElement*(session: Session, selector: string, strategy=CssSelector, timeout=20000, pollTime=50, waitCondition=elementIsSome): Option[Element]

proc click*(session: Session, element: string, strategy=CssSelector) =
  let el = session.waitForElement(element, strategy)
  el.get().click()

proc sendKeys*(session: Session, element, keys: string) =
  let el = session.waitForElement(element)
  el.get().sendKeys(keys)

proc clear*(session: Session, element: string) =
  let el = session.waitForElement(element)
  el.get().clear()

proc sendKeys*(session: Session, element: string, keys: varargs[Key]) =
  let el = session.waitForElement(element)

  # focus
  el.get().click()
  for key in keys:
    session.press(key)

proc ensureExists*(session: Session, element: string, strategy=CssSelector) =
  discard session.waitForElement(element, strategy)

template check*(session: Session, element: string, function: untyped) =
  let el = session.waitForElement(element)
  check function(el)

template check*(session: Session, element: string,
                strategy: LocationStrategy, function: untyped) =
  let el = session.waitForElement(element, strategy)
  check function(el)

proc setColor*(session: Session, element, color: string, strategy=CssSelector) =
  let el = session.waitForElement(element, strategy)
  discard session.execute("arguments[0].setAttribute('value', '" & color & "')", el.get())

proc checkIsNone*(session: Session, element: string, strategy=CssSelector) =
  discard session.waitForElement(element, strategy, waitCondition=elementIsNone)

proc checkText*(session: Session, element, expectedValue: string) =
  let el = session.waitForElement(element)
  check el.get().getText() == expectedValue

proc waitForElement*(
  session: Session, selector: string, strategy=CssSelector,
  timeout=20000, pollTime=50,
  waitCondition=elementIsSome
): Option[Element] =
  var waitTime = 0

  when actionDelayMs > 0:
    sleep(actionDelayMs)

  while true:
    try:
      let loading = session.findElement(selector, strategy)
      if waitCondition(loading):
        return loading
    finally:
      discard
    sleep(pollTime)
    waitTime += pollTime

    if waitTime > timeout:
      doAssert false, "Wait for load time exceeded"

proc waitForElements*(
  session: Session, selector: string, strategy=CssSelector,
  timeout=20000, pollTime=50
): seq[Element] =
  var waitTime = 0

  when actionDelayMs > 0:
    sleep(actionDelayMs)

  while true:
    let loading = session.findElements(selector, strategy)
    if loading.len > 0:
      return loading
    sleep(pollTime)
    waitTime += pollTime

    if waitTime > timeout:
      doAssert false, "Wait for load time exceeded"

proc setUserRank*(session: Session, baseUrl, user, rank: string) =
  with session:
    navigate(baseUrl & "profile/" & user)

    click "#settings-tab"

    click "#rank-field"
    click("#rank-field option#rank-" & rank.toLowerAscii)

    click "#save-btn"

proc logout*(session: Session) =
  with session:
    click "#profile-btn"
    click "#profile-btn #logout-btn"

    # Verify we have logged out by looking for the log in button.
    ensureExists "#login-btn"

proc login*(session: Session, user, password: string) =
  with session:
    click "#login-btn"

    clear "#login-form input[name='username']"
    clear "#login-form input[name='password']"

    sendKeys "#login-form input[name='username']", user
    sendKeys "#login-form input[name='password']", password

    sendKeys "#login-form input[name='password']", Key.Enter

    # Verify that the user menu has been initialised properly.
    click "#profile-btn"
    checkText "#profile-btn #profile-name", user
    click "#profile-btn"

proc register*(session: Session, user, password: string, verify = true) =
  with session:
    click "#signup-btn"

    clear "#signup-form input[name='email']"
    clear "#signup-form input[name='username']"
    clear "#signup-form input[name='password']"

    sendKeys "#signup-form input[name='email']", user & "@" & user & ".com"
    sendKeys "#signup-form input[name='username']", user
    sendKeys "#signup-form input[name='password']", password

    click "#signup-modal .create-account-btn"

    if verify:
      with session:
        # Verify that the user menu has been initialised properly.
        click "#profile-btn"
        checkText "#profile-btn #profile-name", user
        # close menu
        click "#profile-btn"

proc createThread*(session: Session, title, content: string) =
  with session:
    click "#new-thread-btn"

    sendKeys "#thread-title", title
    sendKeys "#reply-textarea", content

    click "#create-thread-btn"

    checkText "#thread-title .title-text", title
    checkText ".original-post div.post-content", content
