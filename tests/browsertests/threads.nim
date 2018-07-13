import unittest, options, os, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  waitForLoad(session)

  login(session, "admin", "admin")

  test "can create thread":
    let newThreadBtn = session.findElement("#new-thread-btn").get()
    newThreadBtn.click()

    waitForLoad(session)

    let newThread = session.findElement("#new-thread")
    check newThread.isSome()

    let createThreadBtn = session.findElement("#create-thread-btn")
    check createThreadBtn.isSome()


    let threadTitle = session.findElement("#thread-title")
    check threadTitle.isSome()

    let replyBox = session.findElement("#reply-textarea")
    check replyBox.isSome()

    threadTitle.get().sendKeys("This is a thread title!")
    replyBox.get().sendKeys("This is content.")

    createThreadBtn.get().click()

    waitForLoad(session)

    let newThreadTitle = session.findElement("#thread-title")
    check newThreadTitle.isSome()

    check newThreadTitle.get().getText() == "This is a thread title!"

    let content = session.findElement(".original-post div.post-content")
    check content.isSome()

    check content.get().getText() == "This is content."
