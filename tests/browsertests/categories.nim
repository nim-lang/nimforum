import unittest, options, os, common

import webdriver

proc selectCategory(session: Session, name: string) =
  with session:
    click "#category-selection .dropdown-toggle"

    click "#category-selection ." & name


proc categoriesTests(session: Session, baseUrl: string) =
  let
    title = "Category Test"
    content = "Choosing category test"

  with session:
    navigate baseUrl
    wait()
    login "user", "user"

  test "can create category thread":
    with session:
      click "#new-thread-btn"
      wait()

      sendKeys "#thread-title", title

      selectCategory "fun"

      sendKeys "#reply-textarea", content

      click "#create-thread-btn"
      wait()

      checkText "#thread-title .category", "Fun"

      navigate baseUrl
      wait()

      ensureExists title, LinkTextSelector

  session.logout()

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)
  session.wait()

  categoriesTests(session, baseUrl)

  session.navigate(baseUrl)
  session.wait()