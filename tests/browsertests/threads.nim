import unittest, options, os, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  let
    titleStr = "This is a thread title!"
    contentStr = "This is content"

  suite "thread tests":
    session.navigate(baseUrl)
    waitForLoad(session)
    login(session, "admin", "admin")

    setup:
      session.navigate(baseUrl)
      waitForLoad(session)

    test "can create thread":
      with session:
        click "#new-thread-btn"
        wait()

        sendKeys "#thread-title", titleStr
        sendKeys "#reply-textarea", contentStr

        click "#create-thread-btn"
        wait()

        checkText "#thread-title", titleStr
        checkText ".original-post div.post-content", contentStr

    test "try create duplicate thread":
      with session:
        click "#new-thread-btn"
        wait()
        ensureExists "#new-thread"

        sendKeys "#thread-title", titleStr
        sendKeys "#reply-textarea", contentStr

        click "#create-thread-btn"

        wait()

        ensureExists "#new-thread p.text-error"

    test "can edit post":
      let modificationText = " and I edited it!"
      with session:
        click titleStr, LinkTextSelector
        wait()

        click ".post-buttons .edit-button"
        wait()

        sendKeys ".original-post #reply-textarea", modificationText
        click ".edit-buttons .save-button"
        wait()

        checkText ".original-post div.post-content", contentStr & modificationText

    test "can like thread":
      # logout admin and login to regular user
      logout(session)
      login(session, "user", "user")

      with session:
        click titleStr, LinkTextSelector
        wait()

        click ".post-buttons .like-button"

        checkText ".post-buttons .like-button .like-count", "1"

      logout(session)
      session.navigate(baseUrl)
      waitForLoad(session)
      login(session, "admin", "admin")

    test "can delete thread":
      with session:
        click titleStr, LinkTextSelector
        wait()

        click ".post-buttons .delete-button"
        wait()

        # click delete confirmation
        click "#delete-modal .delete-btn"
        wait()

        # Make sure the forum post is gone
        checkIsNone titleStr, LinkTextSelector

    session.navigate(baseUrl)
    session.wait()
    logout(session)
