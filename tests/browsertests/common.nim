import os, options
import webdriver

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

proc logout*(session: Session) =
  # Check whether we can log out.
  let logoutLink = session.findElement(
    "Logout",
    LinkTextSelector
  ).get()
  logoutLink.click()

proc login*(session: Session, user, password: string) =
  let logIn = session.findElement("#login-btn").get()
  logIn.click()

  let usernameField = session.findElement(
    "#login-form input[name='username']"
  )

  let passwordField = session.findElement(
    "#login-form input[name='password']"
  )

  usernameField.get().sendKeys("admin")
  passwordField.get().sendKeys("admin")
  passwordField.get().click() # Focus field.
  session.press(Key.Enter)

  waitForLoad(session, 5000)