import unittest, options, os

import webdriver

proc waitForLoad(session: Session, timeout=20000) =
  var waitTime = 0
  sleep(2000)

  while true:
    let loading = session.findElement(".loading")
    if loading.isNone: return
    sleep(1000)
    waitTime += 1000

    if waitTime > timeout:
      doAssert false, "Wait for load time exceeded"

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  waitForLoad(session)

  # Sanity checks
  test "shows sign up":
    let signUp = session.findElement("#signup-btn")
    check signUp.get().getText() == "Sign up"

  test "shows log in":
    let logIn = session.findElement("#login-btn")
    check logIn.get().getText() == "Log in"

  test "is empty":
    let thread = session.findElement("tr > td.thread-title")
    check thread.isNone()

  # Logging in
  test "can login":
    let logIn = session.findElement("#login-btn").get()
    logIn.click()

    let usernameField = session.findElement(
      "#login-form input[name='username']"
    )
    check usernameField.isSome()
    let passwordField = session.findElement(
      "#login-form input[name='password']"
    )
    check passwordField.isSome()

    usernameField.get().sendKeys("admin")
    passwordField.get().sendKeys("admin")
    passwordField.get().click() # Focus field.
    session.press(Key.Enter)

    waitForLoad(session, 5000)

    # Verify that the user menu has been initialised properly.
    let profileButton = session.findElement(
      "#main-navbar figure.avatar"
    ).get()
    profileButton.click()

    let profileName = session.findElement(
      "#main-navbar .menu-right div.tile-content"
    ).get()

    check profileName.getText() == "admin"

