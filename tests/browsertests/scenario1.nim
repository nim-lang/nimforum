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
  test "can login/logout":
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

    # Check whether we can log out.
    let logoutLink = session.findElement(
      "Logout",
      LinkTextSelector
    ).get()
    logoutLink.click()

    # Verify we have logged out by looking for the log in button.
    check session.findElement("#login-btn").isSome()

  test "can register":
    let signup = session.findElement("#signup-btn").get()
    signup.click()

    let emailField = session.findElement(
      "#signup-form input[name='email']"
    ).get()
    let usernameField = session.findElement(
      "#signup-form input[name='username']"
    ).get()
    let passwordField = session.findElement(
      "#signup-form input[name='password']"
    ).get()

    emailField.sendKeys("test@test.com")
    usernameField.sendKeys("test")
    passwordField.sendKeys("test")

    let createAccount = session.findElement(
      "#signup-modal .modal-footer .btn-primary"
    ).get()

    createAccount.click()

    waitForLoad(session, 5000)

    # Verify that the user menu has been initialised properly.
    let profileButton = session.findElement(
      "#main-navbar figure.avatar"
    ).get()
    profileButton.click()

    let profileName = session.findElement(
      "#main-navbar .menu-right div.tile-content"
    ).get()

    check profileName.getText() == "test"