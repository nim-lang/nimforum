import unittest, options, os

import webdriver

proc waitForLoad(session: Session) =
  sleep(2000)

  while true:
    let loading = session.findElement(".loading")
    if loading.isNone: return
    sleep(1000)

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  waitForLoad(session)

  # Sanity checks
  test "shows sign up":
    let signUp = session.findElement("#signup-btn")
    check signUp.get().getText() == "Sign up"

  test "shows log in":
    let signUp = session.findElement("#login-btn")
    check signUp.get().getText() == "Log in"

  test "is empty":
    let thread = session.findElement("tr > td.thread-title")
    check thread.isNone()