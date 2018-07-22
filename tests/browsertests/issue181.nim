import unittest, options, os, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  waitForLoad(session)

  test "can see banned posts":
    with session:
      register("issue181", "issue181")
      logout(baseUrl)

      # Change rank to `user` so they can post.
      login(baseUrl, "admin", "admin")
      setUserRank(baseUrl, "issue181", "user")
      logout(baseUrl)

      login(baseUrl, "issue181", "issue181")

      const title = "Testing issue 181."
      createThread(title, "Test for issue #181")

      logout(baseUrl)

      login(baseUrl, "admin", "admin")

      # Ban our user.
      setUserRank(baseUrl, "issue181", "banned")

      # Make sure the banned user's thread is still visible.
      navigate(baseUrl)
      wait()
      ensureExists("tr.banned")
      checkText("tr.banned .thread-title > a", title)
      logout(baseUrl)
      checkText("tr.banned .thread-title > a", title)