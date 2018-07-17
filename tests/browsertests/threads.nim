import unittest, options, os, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  let
    userTitleStr = "This is a user thread!"
    userContentStr = "A user has filled this out"

    adminTitleStr = "This is a thread title!"
    adminContentStr = "This is content"

  suite "user thread tests":
    session.navigate(baseUrl)
    session.wait()
    login(session, "user", "user")

    setup:
      session.navigate(baseUrl)
      session.wait()

    test "can create thread":
      with session:
        click "#new-thread-btn"
        wait()

        sendKeys "#thread-title", userTitleStr
        sendKeys "#reply-textarea", userContentStr

        click "#create-thread-btn"
        wait()

        checkText "#thread-title", userTitleStr
        checkText ".original-post div.post-content", userContentStr

    session.navigate(baseUrl)
    session.wait()
    logout(session)

  suite "admin thread tests":
    session.navigate(baseUrl)
    session.wait()
    login(session, "admin", "admin")

    setup:
      session.navigate(baseUrl)
      session.wait()

    test "can create thread":
      with session:
        click "#new-thread-btn"
        wait()

        sendKeys "#thread-title", adminTitleStr
        sendKeys "#reply-textarea", adminContentStr

        click "#create-thread-btn"
        wait()

        checkText "#thread-title", adminTitleStr
        checkText ".original-post div.post-content", adminContentStr

    test "try create duplicate thread":
      with session:
        click "#new-thread-btn"
        wait()
        ensureExists "#new-thread"

        sendKeys "#thread-title", adminTitleStr
        sendKeys "#reply-textarea", adminContentStr

        click "#create-thread-btn"

        wait()

        ensureExists "#new-thread p.text-error"

    test "can edit post":
      let modificationText = " and I edited it!"
      with session:
        click adminTitleStr, LinkTextSelector
        wait()

        click ".post-buttons .edit-button"
        wait()

        sendKeys ".original-post #reply-textarea", modificationText
        click ".edit-buttons .save-button"
        wait()

        checkText ".original-post div.post-content", adminContentStr & modificationText

    test "can like thread":
      # Try to like the user thread above

      with session:
        click userTitleStr, LinkTextSelector
        wait()

        click ".post-buttons .like-button"

        checkText ".post-buttons .like-button .like-count", "1"

    test "can delete thread":
      with session:
        click adminTitleStr, LinkTextSelector
        wait()

        click ".post-buttons .delete-button"
        wait()

        # click delete confirmation
        click "#delete-modal .delete-btn"
        wait()

        # Make sure the forum post is gone
        checkIsNone adminTitleStr, LinkTextSelector

    session.navigate(baseUrl)
    session.wait()
    logout(session)
