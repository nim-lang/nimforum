import unittest, options, os, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  waitForLoad(session)

  test "can see banned posts":
    with session:
      register("issue181", "issue181")
      logout()

      # Change rank to `user` so they can post.
      login("admin", "admin")

      navigate(baseUrl & "profile/user")
      wait()
      changeRank("user")
      logout()

      login("issue181", "issue181")

      const title = "Testing issue 181."
      createThread(title, "Test for issue #181")

      logout()
      wait()

      login("admin", "admin")

      # Ban our user.
      navigate(baseUrl & "profile/issue181")
      changeRank("banned")

      # Make sure the banned user's thread is still visible.
      navigate(baseUrl)
      ensureExists("tr.banned")
      checkText("tr.banned .thread-title > a", title)
      logout()
      checkText("tr.banned .thread-title > a", title)

  session.navigate(baseUrl)
  session.wait()
  logout(session)
