import unittest, options, os, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  waitForLoad(session)

  # Sanity checks
  test "shows sign up":
    session.checkText("#signup-btn", "Sign up")

  test "shows log in":
    session.checkText("#login-btn", "Log in")

  test "is empty":
    session.checkIsNone("tr > td.thread-title")

  # Logging in
  test "can login/logout":
    with session:
      click "#login-btn"

      sendKeys "#login-form input[name='username']", "admin"
      sendKeys "#login-form input[name='password']", "admin"

      sendKeys "#login-form input[name='password']", Key.Enter
      wait()

      # Verify that the user menu has been initialised properly.
      click "#profile-btn"
      checkText "#profile-btn #profile-name", "admin"

      # Check whether we can log out.
      click "#logout-btn"
      # Verify we have logged out by looking for the log in button.
      ensureExists "#login-btn"

  test "can register":
    with session:
      click "#signup-btn"

      sendKeys "#signup-form input[name='email']", "test@test.com"
      sendKeys "#signup-form input[name='username']", "test"
      sendKeys "#signup-form input[name='password']", "test"

      click "#signup-modal .create-account-btn"
      wait()

      # Verify that the user menu has been initialised properly.
      click "#profile-btn"
      checkText "#profile-btn #profile-name", "test"
      # close menu
      click "#profile-btn"

  session.navigate(baseUrl)
  session.wait()
  logout(session)
