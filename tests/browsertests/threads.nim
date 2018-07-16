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

    logout(session)
