import unittest, common

import webdriver

proc test*(session: Session, baseUrl: string) =
  session.navigate(baseUrl)

  test "can see banned posts":
    with session:
      register("issue181", "issue181")
      logout()

      # Change rank to `user` so they can post.
      login("admin", "admin")
      setUserRank(baseUrl, "issue181", "user")
      logout()

      login("issue181", "issue181")
      navigate(baseUrl)

      const title = "Testing issue 181."
      createThread(title, "Test for issue #181")

      logout()

      login("admin", "admin")

      # Ban our user.
      setUserRank(baseUrl, "issue181", "banned")

      # Make sure the banned user's thread is still visible.
      navigate(baseUrl)
      ensureExists("tr.banned")
      checkText("tr.banned .thread-title > a", title)
      logout()
      checkText("tr.banned .thread-title > a", title)
