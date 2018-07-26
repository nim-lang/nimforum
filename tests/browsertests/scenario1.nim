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
      login("admin", "admin")

      # Check whether we can log out.
      logout()
      # Verify we have logged out by looking for the log in button.
      ensureExists "#login-btn"

  test "can register":
    with session:
      register("test", "test")

  session.logout()
