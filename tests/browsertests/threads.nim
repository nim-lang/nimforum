import unittest, common

import webdriver

let
  userTitleStr = "This is a user thread!"
  userContentStr = "A user has filled this out"

  adminTitleStr = "This is a thread title!"
  adminContentStr = "This is content"

proc banUser(session: Session, baseUrl: string) =
  with session:
    login "admin", "admin"
    setUserRank baseUrl, "user", "banned"
    logout()

proc unBanUser(session: Session, baseUrl: string) =
  with session:
    login "admin", "admin"
    setUserRank baseUrl, "user", "user"
    logout()

proc userTests(session: Session, baseUrl: string) =
  suite "user thread tests":
    session.login("user", "user")

    setup:
      session.navigate(baseUrl)

    test "can create thread":
      with session:
        click "#new-thread-btn"

        sendKeys "#thread-title", userTitleStr
        sendKeys "#reply-textarea", userContentStr

        click "#create-thread-btn"

        checkText "#thread-title .title-text", userTitleStr
        checkText ".original-post div.post-content", userContentStr

    test "can delete thread":
      with session:
        # create thread to be deleted
        click "#new-thread-btn"

        sendKeys "#thread-title", "To be deleted"
        sendKeys "#reply-textarea", "This thread is to be deleted"

        click "#create-thread-btn"

        click ".post-buttons .delete-button"

        # click delete confirmation
        click "#delete-modal .delete-btn"

        # Make sure the forum post is gone
        checkIsNone "To be deleted", LinkTextSelector

    test "cannot (un)pin thread":
      with session:
        navigate(baseUrl)

        click "#new-thread-btn"

        sendKeys "#thread-title", "Unpinnable"
        sendKeys "#reply-textarea", "Cannot (un)pin as an user"

        click "#create-thread-btn"

        checkIsNone "#pin-btn"

    test "cannot lock threads":
      with session:
        navigate(baseUrl)

        click "#new-thread-btn"

        sendKeys "#thread-title", "Locking"
        sendkeys "#reply-textarea", "Cannot lock as an user"

        click "#create-thread-btn"

        checkIsNone "#lock-btn"
        navigate(baseUrl)

    session.logout()

proc anonymousTests(session: Session, baseUrl: string) =
  suite "anonymous user tests":
    with session:
      navigate baseUrl

    test "can view banned thread":
      with session:
        ensureExists userTitleStr, LinkTextSelector

    with session:
      navigate baseUrl

proc bannedTests(session: Session, baseUrl: string) =
  suite "banned user thread tests":
    with session:
      navigate baseUrl
      login "banned", "banned"

    test "can't start thread":
      with session:
        click "#new-thread-btn"

        sendKeys "#thread-title", "test"
        sendKeys "#reply-textarea", "test"

        click "#create-thread-btn"

        ensureExists "#new-thread p.text-error"

    session.logout()

proc adminTests(session: Session, baseUrl: string) =
  suite "admin thread tests":
    session.login("admin", "admin")

    setup:
      session.navigate(baseUrl)

    test "can view banned thread":
      with session:
        ensureExists userTitleStr, LinkTextSelector

    test "can create thread":
      with session:
        click "#new-thread-btn"

        sendKeys "#thread-title", adminTitleStr
        sendKeys "#reply-textarea", adminContentStr

        click "#create-thread-btn"

        checkText "#thread-title .title-text", adminTitleStr
        checkText ".original-post div.post-content", adminContentStr

    test "try create duplicate thread":
      with session:
        click "#new-thread-btn"
        ensureExists "#new-thread"

        sendKeys "#thread-title", adminTitleStr
        sendKeys "#reply-textarea", adminContentStr

        click "#create-thread-btn"

        ensureExists "#new-thread p.text-error"

    test "can edit post":
      let modificationText = " and I edited it!"
      with session:
        click adminTitleStr, LinkTextSelector

        click ".post-buttons .edit-button"

        sendKeys ".original-post #reply-textarea", modificationText
        click ".edit-buttons .save-button"

        checkText ".original-post div.post-content", adminContentStr & modificationText

    test "can like thread":
      # Try to like the user thread above

      with session:
        click userTitleStr, LinkTextSelector

        click ".post-buttons .like-button"

        checkText ".post-buttons .like-button .like-count", "1"

    test "can delete thread":
      with session:
        click adminTitleStr, LinkTextSelector

        click ".post-buttons .delete-button"

        # click delete confirmation
        click "#delete-modal .delete-btn"

        # Make sure the forum post is gone
        checkIsNone adminTitleStr, LinkTextSelector

    test "Can pin a thread":
      with session:
        click "#new-thread-btn"
        sendKeys "#thread-title", "Pinned post"
        sendKeys "#reply-textarea", "A pinned post"
        click "#create-thread-btn"

        navigate(baseUrl)
        click "#new-thread-btn"
        sendKeys "#thread-title", "Normal post"
        sendKeys "#reply-textarea", "A normal post"
        click "#create-thread-btn"

        navigate(baseUrl)
        click "Pinned post", LinkTextSelector
        click "#pin-btn"
        checkText "#pin-btn", "Unpin Thread"

        navigate(baseUrl)

        # Make sure pin exists
        ensureExists "#threads-list .thread-1 .thread-title i"

        checkText "#threads-list .thread-1 .thread-title a", "Pinned post"
        checkText "#threads-list .thread-2 .thread-title a", "Normal post"

    test "Can unpin a thread":
      with session:
        click "Pinned post", LinkTextSelector
        click "#pin-btn"
        checkText "#pin-btn", "Pin Thread"

        navigate(baseUrl)

        checkIsNone "#threads-list .thread-2 .thread-title i"

        checkText "#threads-list .thread-1 .thread-title a", "Normal post"
        checkText "#threads-list .thread-2 .thread-title a", "Pinned post"

    test "Can lock a thread":
      with session:
        click "Locking", LinkTextSelector
        click "#lock-btn"

        ensureExists "i .fas .fa-lock .fa-xs"

    test "Can unlock a thread":
      with session:
        click "Locking", LinkTextSelector       
        click "#lock-btn"

        checkIsNone "#thread-title i .fas .fa-lock fa-xs"

    session.logout()

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  userTests(session, baseUrl)

  # banUser(session, baseUrl)

  # bannedTests(session, baseUrl)
  # anonymousTests(session, baseUrl)
  adminTests(session, baseUrl)

  # unBanUser(session, baseUrl)

  session.navigate(baseUrl)
