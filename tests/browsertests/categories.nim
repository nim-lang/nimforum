import unittest, options, common, os

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

    test "can navigate to categories page":
      with session:
        click "#categories-btn"

        ensureExists "#categories-list"

    test "can view post under category":
      with session:

        # create a few threads
        click "#new-thread-btn"
        sendKeys "#thread-title", "Post 1"

        selectCategory "fun"
        sendKeys "#reply-textarea", "Post 1"

        click "#create-thread-btn"
        navigate baseUrl


        click "#new-thread-btn"
        sendKeys "#thread-title", "Post 2"

        selectCategory "announcements"
        sendKeys "#reply-textarea", "Post 2"

        click "#create-thread-btn"
        navigate baseUrl


        click "#new-thread-btn"
        sendKeys "#thread-title", "Post 3"

        selectCategory "default"
        sendKeys "#reply-textarea", "Post 3"

        click "#create-thread-btn"
        navigate baseUrl


        click "#categories-btn"
        ensureExists "#categories-list"

        click "#category-default"
        checkText "#threads-list .thread-title", "Post 3"
        for element in session.waitForElements("#threads-list .category-name"):
          # Have to user "innerText" because elements are hidden on this page
          assert element.getProperty("innerText") == "Default"

        selectCategory "announcements"
        checkText "#threads-list .thread-title", "Post 2"
        for element in session.waitForElements("#threads-list .category-name"):
          assert element.getProperty("innerText") == "Announcements"

        selectCategory "fun"
        checkText "#threads-list .thread-title", "Post 1"
        for element in session.waitForElements("#threads-list .category-name"):
          assert element.getProperty("innerText") == "Fun"

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

      test "category adding disabled on admin logout":
        with session:
          navigate(baseUrl & "c/0")
          ensureExists "#add-category"
          logout()

          checkIsNone "#add-category"
          navigate baseUrl

          login "admin", "admin"

    session.logout()

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  categoriesUserTests(session, baseUrl)
  categoriesAdminTests(session, baseUrl)

  session.navigate(baseUrl)
