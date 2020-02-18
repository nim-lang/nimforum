import unittest, options, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

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
      login("admin", "admin")

      # Check whether we can log out.
      logout()
      # Verify we have logged out by looking for the log in button.
      ensureExists "#login-btn"

  test "can register":
    with session:
      register("test", "test")
      logout()

  test "can't register same username with different case":
    with session:
      register "test1", "test1", verify = false
      logout()

      navigate baseUrl

      register "TEst1", "test1", verify = false

      ensureExists "#signup-form .has-error"
      navigate baseUrl