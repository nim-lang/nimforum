import unittest, options, common

import webdriver

proc selectCategory(session: Session, name: string) =
  with session:
    click "#category-selection .dropdown-toggle"
    click "#category-selection ." & name

proc categoriesUserTests(session: Session, baseUrl: string) =
  let
    title = "Category Test"
    content = "Choosing category test"

  suite "user tests":

    with session:
      navigate baseUrl
      login "user", "user"

    setup:
      with session:
        navigate baseUrl

    test "no category add available":
      with session:
        click "#new-thread-btn"

        checkIsNone "#add-category"

    test "can create category thread":
      with session:
        click "#new-thread-btn"
        sendKeys "#thread-title", title

        selectCategory "fun"
        sendKeys "#reply-textarea", content

        click "#create-thread-btn"
        checkText "#thread-title .category", "Fun"

        navigate baseUrl

        ensureExists title, LinkTextSelector

    session.logout()

proc categoriesAdminTests(session: Session, baseUrl: string) =
  let
    name = "Category Test"
    color = "Creating category test"
    description = "This is a description"

  suite "admin tests":
    with session:
      navigate baseUrl
      login "admin", "admin"

    test "can create category":
      with session:
        click "#new-thread-btn"

        ensureExists "#add-category"

        click "#add-category .plus-btn"

        clear "#add-category input[name='name']"
        clear "#add-category input[name='color']"
        clear "#add-category input[name='description']"

        sendKeys "#add-category input[name='name']", name
        sendKeys "#add-category input[name='color']", color
        sendKeys "#add-category input[name='description']", description

        click "#add-category #add-category-btn"

        checkText "#category-selection .selected-category", name

    session.logout()

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  categoriesUserTests(session, baseUrl)
  categoriesAdminTests(session, baseUrl)

  session.navigate(baseUrl)