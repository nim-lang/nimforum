#
#
#              The Nim Forum
#        (c) Copyright 2012 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#
import system except Thread
import
  os, strutils, times, md5, strtabs, math, db_sqlite,
  scgi, jester, asyncdispatch, asyncnet, sequtils,
  parseutils, random, rst, recaptcha, json, re, sugar,
  strformat, logging
import cgi except setCookie
import options

import auth, email, utils, buildcss

import frontend/threadlist except User
import frontend/[
  category, postlist, error, header, post, profile, user, karaxutils, search
]

from htmlgen import tr, th, td, span, input

type
  TCrud = enum crCreate, crRead, crUpdate, crDelete

  Session = object of RootObj
    userName, userPass, email: string
    rank: Rank

  TPost = tuple[subject, content: string]

  TForumData = ref object of Session
    req: Request
    userid: string
    config: Config

var
  db: DbConn
  isFTSAvailable: bool
  config: Config
  captcha: ReCaptcha
  mailer: Mailer
  karaxHtml: string

proc init(c: TForumData) =
  c.userPass = ""
  c.userName = ""

  c.userid = ""

proc loggedIn(c: TForumData): bool =
  result = c.userName.len > 0

# --------------- HTML widgets ------------------------------------------------


proc genThreadUrl(c: TForumData, postId = "", action = "",
                  threadid = ""): string =
  result = "/t/" & threadid
  if action != "":
    result.add("?action=" & action)
    if postId != "":
      result.add("&postid=" & postid)
  elif postId != "":
    result.add("#" & postId)
  result = c.req.makeUri(result, absolute = false)


proc getGravatarUrl(email: string, size = 80): string =
  let emailMD5 = email.toLowerAscii.toMD5
  return ("https://www.gravatar.com/avatar/" & $emailMD5 & "?s=" & $size &
     "&d=identicon")



# -----------------------------------------------------------------------------
template `||`(x: untyped): untyped = (if not isNil(x): x else: "")

proc validateCaptcha(recaptchaResp, ip: string) {.async.} =
  # captcha validation:
  if config.recaptchaSecretKey.len > 0:
    var verifyFut = captcha.verify(recaptchaResp, ip)
    yield verifyFut
    if verifyFut.failed:
      raise newForumError(
        "Invalid recaptcha answer", @[]
      )

proc sendResetPassword(
  c: TForumData,
  email: string,
  recaptchaResp: string,
  userIp: string
) {.async.} =
  # Gather some extra information to determine ident hash.
  let row = db.getRow(
    sql"""
      select name, password, email, salt from person
      where email = ? or name = ?
    """,
    email, email
  )
  if row[0] == "":
    raise newForumError("Email or username not found", @["email"])

  await validateCaptcha(recaptchaResp, userIp)

  await sendSecureEmail(
    mailer,
    ResetPassword, c.req,
    row[0], row[1], row[2], row[3]
  )

proc logout(c: TForumData) =
  const query = sql"delete from session where ip = ? and key = ?"
  c.username = ""
  c.userpass = ""
  exec(db, query, c.req.ip, c.req.cookies["sid"])

proc checkLoggedIn(c: TForumData) =
  if not c.req.cookies.hasKey("sid"): return
  let sid = c.req.cookies["sid"]
  if execAffectedRows(db,
       sql("update session set lastModified = DATETIME('now') " &
           "where ip = ? and key = ?"),
           c.req.ip, sid) > 0:
    c.userid = getValue(db,
      sql"select userid from session where ip = ? and key = ?",
      c.req.ip, sid)

    let row = getRow(db,
      sql"select name, email, status from person where id = ?", c.userid)
    c.username = ||row[0]
    c.email = ||row[1]
    c.rank = parseEnum[Rank](||row[2])

    # Update lastOnline
    db.exec(sql"update person set lastOnline = DATETIME('now') where id = ?",
            c.userid)

  else:
    warn("SID not found in sessions. Assuming logged out.")

proc incrementViews(threadId: int) =
  const query = sql"update thread set views = views + 1 where id = ?"
  exec(db, query, threadId)

proc validateRst(c: TForumData, content: string): bool =
  result = true
  try:
    discard rstToHtml(content)
  except EParseError:
    result = false

proc crud(c: TCrud, table: string, data: varargs[string]): SqlQuery =
  case c
  of crCreate:
    var fields = "insert into " & table & "("
    var vals = ""
    for i, d in data:
      if i > 0:
        fields.add(", ")
        vals.add(", ")
      fields.add(d)
      vals.add('?')
    result = sql(fields & ") values (" & vals & ")")
  of crRead:
    var res = "select "
    for i, d in data:
      if i > 0: res.add(", ")
      res.add(d)
    result = sql(res & " from " & table)
  of crUpdate:
    var res = "update " & table & " set "
    for i, d in data:
      if i > 0: res.add(", ")
      res.add(d)
      res.add(" = ?")
    result = sql(res & " where id = ?")
  of crDelete:
    result = sql("delete from " & table & " where id = ?")

proc rateLimitCheck(c: TForumData): bool =
  const query40 =
    sql("SELECT count(*) FROM post where author = ? and " &
        "(strftime('%s', 'now') - strftime('%s', creation)) < 40")
  const query90 =
    sql("SELECT count(*) FROM post where author = ? and " &
        "(strftime('%s', 'now') - strftime('%s', creation)) < 90")
  const query300 =
    sql("SELECT count(*) FROM post where author = ? and " &
        "(strftime('%s', 'now') - strftime('%s', creation)) < 300")
  # TODO Why can't I pass the secs as a param?
  let last40s = getValue(db, query40, c.userId).parseInt
  let last90s = getValue(db, query90, c.userId).parseInt
  let last300s = getValue(db, query300, c.userId).parseInt
  if last40s > 1: return true
  if last90s > 2: return true
  if last300s > 6: return true
  return false


proc verifyIdentHash(
  c: TForumData, name: string, epoch: int64, ident: string
) =
  const query =
    sql"select password, salt, strftime('%s', lastOnline) from person where name = ?"
  var row = getRow(db, query, name)
  if row[0] == "":
    raise newForumError("User doesn't exist.", @["nick"])
  let newIdent = makeIdentHash(name, row[0], epoch, row[1])
  # Check that it hasn't expired.
  let diff = getTime() - epoch.fromUnix()
  if diff.hours > 2:
    raise newForumError("Link expired")
  if newIdent != ident:
    raise newForumError("Invalid ident hash")

proc initialise() =
  randomize()

  config = loadConfig()
  if len(config.recaptchaSecretKey) > 0 and len(config.recaptchaSiteKey) > 0:
    captcha = initReCaptcha(config.recaptchaSecretKey, config.recaptchaSiteKey)
  else:
    doAssert config.isDev, "Recaptcha required for production!"
    warn("No recaptcha secret key specified.")

  mailer = newMailer(config)

  db = open(connection=config.dbPath, user="", password="",
              database="nimforum")
  isFTSAvailable = db.getAllRows(sql("SELECT name FROM sqlite_master WHERE " &
      "type='table' AND name='post_fts'")).len == 1

  buildCSS(config)

  # Read karax.html and set its properties.
  karaxHtml = readFile("public/karax.html") %
    {
      "title": config.title,
      "timestamp": encodeUrl(CompileDate & CompileTime)
    }.newStringTable()


template createTFD() =
  var c {.inject.}: TForumData
  new(c)
  init(c)
  c.req = request
  if request.cookies.len > 0:
    checkLoggedIn(c)

#[ DB functions. TODO: Move to another module? ]#

proc selectUser(userRow: seq[string], avatarSize: int=80): User =
  result = User(
    name: userRow[0],
    avatarUrl: userRow[1].getGravatarUrl(avatarSize),
    lastOnline: userRow[2].parseInt,
    rank: parseEnum[Rank](userRow[3]),
    isDeleted: userRow[4] == "1"
  )

  # Don't give data about a deleted user.
  if result.isDeleted:
    result.name = "DeletedUser"
    result.avatarUrl = getGravatarUrl(result.name & userRow[1], avatarSize)

proc selectPost(postRow: seq[string], skippedPosts: seq[int],
                replyingTo: Option[PostLink], history: seq[PostInfo],
                likes: seq[User]): Post =
  return Post(
    id: postRow[0].parseInt,
    replyingTo: replyingTo,
    author: selectUser(postRow[5..9]),
    likes: likes,
    seen: false, # TODO:
    history: history,
    info: PostInfo(
      creation: postRow[2].parseInt,
      content: postRow[1].rstToHtml()
    ),
    moreBefore: skippedPosts
  )

proc selectReplyingTo(replyingTo: string): Option[PostLink] =
  if replyingTo.len == 0: return

  const replyingToQuery = sql"""
    select p.id, strftime('%s', p.creation), p.thread,
           u.name, u.email, strftime('%s', u.lastOnline), u.status,
           u.isDeleted,
           t.name
    from post p, person u, thread t
    where p.thread = t.id and p.author = u.id and p.id = ? and p.isDeleted = 0;
  """

  let row = getRow(db, replyingToQuery, replyingTo)
  if row[0].len == 0: return

  return some(PostLink(
    creation: row[1].parseInt(),
    topic: row[^1],
    threadId: row[2].parseInt(),
    postId: row[0].parseInt(),
    author: some(selectUser(row[3..7]))
  ))

proc selectHistory(postId: int): seq[PostInfo] =
  const historyQuery = sql"""
    select strftime('%s', creation), content from postRevision
    where original = ?
    order by creation asc;
  """

  result = @[]
  for row in getAllRows(db, historyQuery, $postId):
    result.add(PostInfo(
      creation: row[0].parseInt(),
      content: row[1].rstToHtml()
    ))

proc selectLikes(postId: int): seq[User] =
  const likeQuery = sql"""
    select u.name, u.email, strftime('%s', u.lastOnline), u.status,
           u.isDeleted
    from like h, person u
    where h.post = ? and h.author = u.id
    order by h.creation asc;
  """

  result = @[]
  for row in getAllRows(db, likeQuery, $postId):
    result.add(selectUser(row))

proc selectThreadAuthor(threadId: int): User =
  const authorQuery =
    sql"""
      select name, email, strftime('%s', lastOnline), status, isDeleted
      from person where id in (
        select author from post
        where thread = ?
        order by id
        limit 1
      )
    """

  return selectUser(getRow(db, authorQuery, threadId))

proc selectThread(threadRow: seq[string]): Thread =
  const postsQuery =
    sql"""select count(*), strftime('%s', creation) from post
          where thread = ?
          order by creation asc limit 1;"""
  const usersListQuery =
    sql"""
      select name, email, strftime('%s', lastOnline), status, u.isDeleted,
             count(*)
      from person u, post p where p.author = u.id and p.thread = ?
      group by name order by count(*) desc limit 5;
    """

  let posts = getRow(db, postsQuery, threadRow[0])

  var thread = Thread(
    id: threadRow[0].parseInt,
    topic: threadRow[1],
    category: Category(
      id: threadRow[5].parseInt,
      name: threadRow[6],
      description: threadRow[7],
      color: threadRow[8]
    ),
    users: @[],
    replies: posts[0].parseInt-1,
    views: threadRow[2].parseInt,
    activity: threadRow[3].parseInt,
    creation: posts[1].parseInt,
    isLocked: threadRow[4] == "1",
    isSolved: false, # TODO: Add a field to `post` to identify the solution.
  )

  # Gather the users list.
  for user in getAllRows(db, usersListQuery, thread.id):
    thread.users.add(selectUser(user))

  # Grab the author.
  thread.author = selectThreadAuthor(thread.id)

  return thread

proc executeReply(c: TForumData, threadId: int, content: string,
                  replyingTo: Option[int]): int64 =
  # TODO: Refactor TForumData.
  assert c.loggedIn()

  if not canPost(c.rank):
    case c.rank
    of EmailUnconfirmed:
      raise newForumError("You need to confirm your email before you can post")
    else:
      raise newForumError("You are not allowed to post")

  if rateLimitCheck(c):
    raise newForumError("You're posting too fast!")

  if content.strip().len == 0:
    raise newForumError("Message cannot be empty")

  if not validateRst(c, content):
    raise newForumError("Message needs to be valid RST", @["msg"])

  # Ensure that the thread isn't locked.
  let isLocked = getValue(
    db,
    sql"""
      select isLocked from thread where id in (
        select thread from post where id = ?
      )
    """,
    threadId
  )
  if isLocked.len == 0:
    raise newForumError("Thread not found.")

  if isLocked == "1":
    raise newForumError("Cannot reply to a locked thread.")

  let retID = insertID(
    db,
    crud(crCreate, "post", "author", "ip", "content", "thread", "replyingTo"),
    c.userId, c.req.ip, content, $threadId,
    if replyingTo.isSome(): $replyingTo.get()
    else: nil
  )
  discard tryExec(
    db,
    crud(crCreate, "post_fts", "id", "content"),
    retID.int, content
  )

  exec(db, sql"update thread set modified = DATETIME('now') where id = ?",
       $threadId)

  return retID

proc updatePost(c: TForumData, postId: int, content: string,
                subject: Option[string]) =
  ## Updates an existing post.
  assert c.loggedIn()

  let postQuery = sql"""
    select author, strftime('%s', creation), thread
    from post where id = ?
  """

  let postRow = getRow(db, postQuery, postId)

  # Verify that the current user has permissions to edit the specified post.
  let creation = fromUnix(postRow[1].parseInt)
  let isArchived = (getTime() - creation).weeks > 8
  let canEdit = c.rank == Admin or c.userid == postRow[0]
  if isArchived:
    raise newForumError("This post is archived and can no longer be edited")
  if not canEdit:
    raise newForumError("You cannot edit this post")

  if not validateRst(c, content):
    raise newForumError("Message needs to be valid RST", @["msg"])

  # Update post.
  # - We create a new postRevision entry for our edit.
  exec(
    db,
    crud(crCreate, "postRevision", "content", "original"),
    content,
    $postId
  )
  # - We set the FTS to the latest content as searching for past edits is not
  #   supported.
  exec(db, crud(crUpdate, "post_fts", "content"), content, $postId)
  # Check if post is the first post of the thread.
  if subject.isSome():
    let threadId = postRow[2]
    let row = db.getRow(sql("""
        select id from post where thread = ? order by id asc
      """), threadId)
    if row[0] == $postId:
      exec(db, crud(crUpdate, "thread", "name"), subject.get(), threadId)

proc executeNewThread(c: TForumData, subject, msg: string): (int64, int64) =
  const
    query = sql"""
      insert into thread(name, views, modified) values (?, 0, DATETIME('now'))
    """

  assert c.loggedIn()

  if not canPost(c.rank):
    case c.rank
    of EmailUnconfirmed:
      raise newForumError("You need to confirm your email before you can post")
    else:
      raise newForumError("You are not allowed to post")

  if subject.len <= 2:
    raise newForumError("Subject is too short", @["subject"])
  if subject.len > 100:
    raise newForumError("Subject is too long", @["subject"])

  if msg.len == 0:
    raise newForumError("Message is empty", @["msg"])

  if not validateRst(c, msg):
    raise newForumError("Message needs to be valid RST", @["msg"])

  if rateLimitCheck(c):
    raise newForumError("You're posting too fast!")

  result[0] = tryInsertID(db, query, subject).int
  if result[0] < 0:
    raise newForumError("Subject already exists", @["subject"])

  discard tryExec(db, crud(crCreate, "thread_fts", "id", "name"),
                  result[0], subject)
  result[1] = executeReply(c, result[0].int, msg, none[int]())
  discard tryExec(db, sql"insert into post_fts(post_fts) values('optimize')")
  discard tryExec(db, sql"insert into post_fts(thread_fts) values('optimize')")

proc executeLogin(c: TForumData, username, password: string): string =
  ## Performs a login with the specified details.
  ##
  ## Optionally, `username` may contain the email of the user instead.
  const query =
    sql"""
      select id, name, password, email, salt
      from person where (name = ? or email = ?) and isDeleted = 0
    """

  let username = username.strip()
  if username.len == 0:
    raise newForumError("Username cannot be empty", @["username"])

  for row in fastRows(db, query, username, username):
    if row[2] == makePassword(password, row[4], row[2]):
      let key = makeSessionKey()
      exec(
        db,
        sql"insert into session (ip, key, userid) values (?, ?, ?)",
        c.req.ip, key, row[0]
      )
      return key

  raise newForumError("Invalid username or password")

proc validateEmail(email: string, checkDuplicated: bool) =
  if not ('@' in email and '.' in email):
    raise newForumError("Invalid email", @["email"])
  if checkDuplicated:
    if getValue(
      db,
      sql"select email from person where email = ? and isDeleted = 0",
      email
    ).len > 0:
      raise newForumError("Email already exists", @["email"])

proc executeRegister(c: TForumData, name, pass, antibot, userIp,
                     email: string) {.async.} =
  ## Registers a new user.

  # email validation
  validateEmail(email, checkDuplicated=true)

  # Username validation:
  if name.len == 0 or not allCharsInSet(name, UsernameIdent) or name.len > 20:
    raise newForumError("Invalid username", @["username"])
  if getValue(
    db,
    sql"select name from person where name = ? and isDeleted = 0",
    name
  ).len > 0:
    raise newForumError("Username already exists", @["username"])

  # Password validation:
  if pass.len < 4:
    raise newForumError("Please choose a longer password", @["password"])

  await validateCaptcha(antibot, userIp)

  # perform registration:
  var salt = makeSalt()
  let password = makePassword(pass, salt)

  # Send activation email.
  await sendSecureEmail(
    mailer, ActivateEmail, c.req, name, password, email, salt
  )

  # Add account to person table
  exec(db, sql"""
    INSERT INTO person(name, password, email, salt, status, lastOnline)
    VALUES (?, ?, ?, ?, ?, DATETIME('now'))
  """, name, password, email, salt, $EmailUnconfirmed)

proc executeLike(c: TForumData, postId: int) =
  # Verify the post exists and doesn't belong to the current user.
  const postQuery = sql"""
    select u.name from post p, person u
    where p.id = ? and p.author = u.id and p.isDeleted = 0;
  """

  let postAuthor = getValue(db, postQuery, postId)
  if postAuthor.len == 0:
    raise newForumError("Specified post ID does not exist.", @["id"])

  if postAuthor == c.username:
    raise newForumError("You cannot like your own post.")

  # Save the like.
  exec(db, crud(crCreate, "like", "author", "post"), c.userid, postId)

proc executeUnlike(c: TForumData, postId: int) =
  # Verify the post and like exists for the current user.
  const likeQuery = sql"""
    select l.id from like l, person u
    where l.post = ? and l.author = u.id and u.name = ?;
  """

  let likeId = getValue(db, likeQuery, postId, c.username)
  if likeId.len == 0:
    raise newForumError("Like doesn't exist.", @["id"])

  # Delete the like.
  exec(db, crud(crDelete, "like"), likeId)

proc executeLockState(c: TForumData, threadId: int, locked: bool) =
  # Verify that the logged in user has the correct permissions.
  if c.rank < Moderator:
    raise newForumError("You cannot lock this thread.")

  # Save the like.
  exec(db, crud(crUpdate, "thread", "isLocked"), locked.int, threadId)

proc executeDeletePost(c: TForumData, postId: int) =
  # Verify that this post belongs to the user.
  const postQuery = sql"""
    select p.id from post p
    where p.author = ? and p.id = ?
  """
  let id = getValue(db, postQuery, postId, c.username)

  if id.len == 0 and c.rank < Admin:
    raise newForumError("You cannot delete this post")

  # Set the `isDeleted` flag.
  exec(db, crud(crUpdate, "post", "isDeleted"), "1", postId)

proc executeDeleteThread(c: TForumData, threadId: int) =
  # Verify that this thread belongs to the user.
  let author = selectThreadAuthor(threadId)
  if author.name != c.username and c.rank < Admin:
    raise newForumError("You cannot delete this thread")

  # Set the `isDeleted` flag.
  exec(db, crud(crUpdate, "thread", "isDeleted"), "1", threadId)

proc executeDeleteUser(c: TForumData, username: string) =
  # Verify that the current user has the permissions to do this.
  if username != c.username and c.rank < Admin:
    raise newForumError("You cannot delete this user.")

  # Set the `isDeleted` flag.
  exec(db, sql"update person set isDeleted = 1 where name = ?;", username)

  logout(c)

proc updateProfile(
  c: TForumData, username, email: string, rank: Rank
) {.async.} =
  if c.rank < rank:
    raise newForumError("You cannot set a rank that is higher than yours.")

  if c.username != username and c.rank < Moderator:
    raise newForumError("You can't change this profile.")

  # Check if we are only setting the rank.
  if email.len == 0:
    exec(
      db,
      sql"update person set status = ? where name = ?;",
      $rank, username
    )
    return

  # Make sure the rank is set to EmailUnconfirmed when the email changes.
  let row = getRow(
    db,
    sql"select name, password, email, salt from person where name = ?",
    username
  )
  let wasEmailChanged = row[2] != email
  if c.rank < Moderator and wasEmailChanged:
    if rank != EmailUnconfirmed:
      raise newForumError("Rank needs a change when setting new email.")

    await sendSecureEmail(
      mailer, ActivateEmail, c.req, row[0], row[1], row[2], row[3]
    )

  validateEmail(email, checkDuplicated=wasEmailChanged)

  exec(
    db,
    sql"update person set status = ?, email = ? where name = ?;",
    $rank, email, username
  )

include "main.tmpl"

initialise()

routes:

  get "/threads.json":
    var
      start = getInt(@"start", 0)
      count = getInt(@"count", 30)

    const threadsQuery =
      sql"""select t.id, t.name, views, strftime('%s', modified), isLocked,
                   c.id, c.name, c.description, c.color
            from thread t, category c
            where isDeleted = 0 and category = c.id
            order by modified desc limit ?, ?;"""

    let thrCount = getValue(db, sql"select count(*) from thread;").parseInt()
    let moreCount = max(0, thrCount - (start + count))

    var list = ThreadList(threads: @[], lastVisit: 0, moreCount: moreCount)
    for data in getAllRows(db, threadsQuery, start, count):
      let thread = selectThread(data)
      list.threads.add(thread)

    resp $(%list), "application/json"

  get "/posts.json":
    createTFD()
    var
      id = getInt(@"id", -1)
      anchor = getInt(@"anchor", -1)
    cond id != -1
    const
      count = 10

    const threadsQuery =
      sql"""select t.id, t.name, views, strftime('%s', modified), isLocked,
                   c.id, c.name, c.description, c.color
            from thread t, category c
            where t.id = ? and isDeleted = 0 and category = c.id;"""

    let threadRow = getRow(db, threadsQuery, id)
    let thread = selectThread(threadRow)

    let postsQuery =
      sql(
        """select p.id, p.content, strftime('%s', p.creation), p.author,
                  p.replyingTo,
                  u.name, u.email, strftime('%s', u.lastOnline), u.status,
                  u.isDeleted
           from post p, person u
           where u.id = p.author and p.thread = ? and p.isDeleted = 0
           order by p.id"""
      )

    var list = PostList(
      posts: @[],
      history: @[],
      thread: thread
    )
    let rows = getAllRows(db, postsQuery, id, c.userId, c.userId)

    var skippedPosts: seq[int] = @[]
    for i in 0 ..< rows.len:
      let id = rows[i][0].parseInt

      let addDetail = i < count or rows.len-i < count or id == anchor

      if addDetail:
        let replyingTo = selectReplyingTo(rows[i][4])
        let history = selectHistory(id)
        let likes = selectLikes(id)
        let post = selectPost(
          rows[i], skippedPosts, replyingTo, history, likes
        )
        list.posts.add(post)
        skippedPosts = @[]
      else:
        skippedPosts.add(id)

    incrementViews(id)

    resp $(%list), "application/json"

  get "/specific_posts.json":
    createTFD()
    var
      ids = parseJson(@"ids")

    cond ids.kind == JArray
    let intIDs = ids.elems.map(x => x.getInt())
    let postsQuery = sql("""
      select p.id, p.content, strftime('%s', p.creation), p.author,
             p.replyingTo,
             u.name, u.email, strftime('%s', u.lastOnline), u.status,
             u.isDeleted
      from post p, person u
      where u.id = p.author and p.id in ($#)
      order by p.id;
    """ % intIDs.join(",")) # TODO: It's horrible that I have to do this.

    var list: seq[Post] = @[]

    for row in db.getAllRows(postsQuery):
      let history = selectHistory(row[0].parseInt())
      let likes = selectLikes(row[0].parseInt())
      list.add(selectPost(row, @[], selectReplyingTo(row[4]), history, likes))

    resp $(%list), "application/json"

  get "/post.rst":
    createTFD()
    let postId = getInt(@"id", -1)
    cond postId != -1

    let postQuery = sql"""
      select content from (
        select content, creation from post where id = ?
        union
        select content, creation from postRevision where original = ?
      )
      order by creation desc limit 1;
    """

    let content = getValue(db, postQuery, postId, postId)
    if content.len == 0:
      resp Http404, "Post not found"
    else:
      resp content, "text/x-rst"

  get "/profile.json":
    createTFD()
    var
      username = @"username"

    # Have to do this because SQLITE doesn't support `in` queries with
    # multiple columns :/
    # TODO: Figure out a better way. This is horrible.
    let creatorSubquery = """
        (select $1 from post p
         where p.thread = t.id
         order by p.id asc limit 1)
    """

    let threadsFrom = """
      from thread t, post p
      where ? in $1 and p.id in $2
    """ % [creatorSubquery % "author", creatorSubquery % "id"]

    let postsFrom = """
      from post p, person u, thread t
      where u.id = p.author and p.thread = t.id and u.name = ?
    """

    let postsQuery = sql("""
      select p.id, strftime('%s', p.creation),
             t.name, t.id
      $1
      order by p.id desc limit 10;
    """ % postsFrom)

    let userQuery = sql("""
      select name, email, strftime('%s', lastOnline), status, isDeleted,
             strftime('%s', creation), id
      from person
      where name = ? and isDeleted = 0
    """)

    var profile = Profile(
      threads: @[],
      posts: @[]
    )

    let userRow = db.getRow(userQuery, username)

    let userID = userRow[^1]
    if userID.len == 0:
      halt()

    profile.user = selectUser(userRow, avatarSize=200)
    profile.joinTime = userRow[^2].parseInt()
    profile.postCount =
      getValue(db, sql("select count(*) " & postsFrom), username).parseInt()
    profile.threadCount =
      getValue(db, sql("select count(*) " & threadsFrom), userID).parseInt()

    if c.rank >= Admin or c.username == username:
      profile.email = some(userRow[1])

    for row in db.getAllRows(postsQuery, username):
      profile.posts.add(
        PostLink(
          creation: row[1].parseInt(),
          topic: row[2],
          threadId: row[3].parseInt(),
          postId: row[0].parseInt()
        )
      )

    let threadsQuery = sql("""
      select t.id, t.name, strftime('%s', p.creation), p.id
      $1
      order by t.id desc
      limit 10;
    """ % threadsFrom)
    for row in db.getAllRows(threadsQuery, userID):
      profile.threads.add(
        PostLink(
          creation: row[2].parseInt(),
          topic: row[1],
          threadId: row[0].parseInt(),
          postId: row[3].parseInt()
        )
      )

    resp $(%profile), "application/json"

  post "/login":
    createTFD()
    let formData = request.formData
    cond "username" in formData
    cond "password" in formData
    try:
      let session = executeLogin(
        c,
        formData["username"].body,
        formData["password"].body
      )
      setCookie("sid", session)
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post "/signup":
    createTFD()
    let formData = request.formData
    if not config.isDev:
      cond "g-recaptcha-response" in formData

    let username = formData["username"].body
    let password = formData["password"].body
    let recaptcha =
      if "g-recaptcha-response" in formData:
        formData["g-recaptcha-response"].body
      else:
        ""
    try:
      await executeRegister(
        c,
        username,
        password,
        recaptcha,
        request.host,
        formData["email"].body
      )
      let session = executeLogin(c, username, password)
      setCookie("sid", session)
      resp Http200, "{}", "application/json"
    except ForumError:
      let exc = (ref ForumError)(getCurrentException())
      resp Http400, $(%exc.data), "application/json"

  get "/status.json":
    createTFD()

    let user =
      if @"logout" == "true":
        logout(c); none[User]()
      elif c.loggedIn():
        some(User(
          name: c.username,
          avatarUrl: c.email.getGravatarUrl(),
          lastOnline: getTime().toUnix(),
          rank: c.rank
        ))
      else:
        none[User]()

    let status = UserStatus(
      user: user,
      recaptchaSiteKey:
        if not config.isDev:
          some(config.recaptchaSiteKey)
        else:
          none[string]()
    )
    resp $(%status), "application/json"

  post "/preview":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "msg" in formData

    let msg = formData["msg"].body
    try:
      let rendered = msg.rstToHtml()
      resp Http200, rendered
    except EParseError:
      let err = PostError(
        errorFields: @[],
        message: getCurrentExceptionMsg()
      )
      resp Http400, $(%err), "application/json"

  post "/createPost":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "msg" in formData
    cond "threadId" in formData

    let msg = formData["msg"].body
    let threadId = getInt(formData["threadId"].body, -1)
    cond threadId != -1

    let replyingToId =
      if "replyingTo" in formData:
        getInt(formData["replyingTo"].body, -1)
      else:
        -1
    let replyingTo =
      if replyingToId == -1: none[int]()
      else: some(replyingToId)

    try:
      let id = executeReply(c, threadId, msg, replyingTo)
      resp Http200, $(%id), "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post "/updatePost":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "msg" in formData
    cond "postId" in formData

    let msg = formData["msg"].body
    let postId = getInt(formData["postId"].body, -1)
    cond postId != -1
    let subject =
      if "subject" in formData:
        some(formData["subject"].body)
      else:
        none[string]()

    try:
      updatePost(c, postId, msg, subject)
      resp Http200, msg.rstToHtml(), "text/html"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post "/newthread":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "msg" in formData
    cond "subject" in formData

    let msg = formData["msg"].body
    let subject = formData["subject"].body
    # TODO: category

    try:
      let res = executeNewThread(c, subject, msg)
      resp Http200, $(%[res[0], res[1]]), "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post re"/(like|unlike)":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "id" in formData

    let postId = getInt(formData["id"].body, -1)
    cond postId != -1

    try:
      case request.path
      of "/like":
        executeLike(c, postId)
      of "/unlike":
        executeUnlike(c, postId)
      else:
        assert false
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post re"/(lock|unlock)":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "id" in formData

    let threadId = getInt(formData["id"].body, -1)
    cond threadId != -1

    try:
      case request.path
      of "/lock":
        executeLockState(c, threadId, true)
      of "/unlock":
        executeLockState(c, threadId, false)
      else:
        assert false
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post re"/delete(Post|Thread)":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "id" in formData

    let id = getInt(formData["id"].body, -1)
    cond id != -1

    try:
      case request.path
      of "/deletePost":
        executeDeletePost(c, id)
      of "/deleteThread":
        executeDeleteThread(c, id)
      else:
        assert false
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post "/deleteUser":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "username" in formData

    let username = formData["username"].body

    try:
      executeDeleteUser(c, username)
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data), "application/json"

  post "/saveProfile":
    createTFD()
    if not c.loggedIn():
      let err = PostError(
        errorFields: @[],
        message: "Not logged in."
      )
      resp Http401, $(%err), "application/json"

    let formData = request.formData
    cond "username" in formData
    cond "email" in formData
    cond "rank" in formData

    let username = formData["username"].body
    let email = formData["email"].body
    let rank = parseEnum[Rank](formData["rank"].body)

    try:
      await updateProfile(c, username, email, rank)
      resp Http200, "{}", "application/json"
    except ForumError:
      let exc = (ref ForumError)(getCurrentException())
      resp Http400, $(%exc.data), "application/json"

  post "/sendResetPassword":
    createTFD()

    let formData = request.formData
    let recaptcha =
      if "g-recaptcha-response" in formData:
        formData["g-recaptcha-response"].body
      else:
        ""

    if not c.loggedIn():
      if not config.isDev:
        if "g-recaptcha-response" notin formData:
          let err = PostError(
            errorFields: @[],
            message: "Not logged in."
          )
          resp Http401, $(%err), "application/json"

    cond "email" in formData
    try:
      await sendResetPassword(
        c, formData["email"].body, recaptcha, request.host
      )
      resp Http200, "{}", "application/json"
    except ForumError:
      let exc = (ref ForumError)(getCurrentException())
      resp Http400, $(%exc.data), "application/json"

  post "/resetPassword":
    createTFD()
    cond(@"nick" != "")
    cond(@"epoch" != "")
    cond(@"ident" != "")
    cond(@"newPassword" != "")
    let epoch = getInt64(@"epoch", -1)
    try:
      verifyIdentHash(c, @"nick", epoch, @"ident")
      var salt = makeSalt()
      let password = makePassword(@"newPassword", salt)

      exec(
        db,
        sql"""
          update person set password = ?, salt = ?,
                            lastOnline = DATETIME('now')
          where name = ?;
        """,
        password, salt, @"nick"
      )

      # Remove all sessions.
      exec(
        db,
        sql"""
          delete from session where userid = (
            select id from person
            where name = ?
          )
        """,
        @"nick"
      )
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data),"application/json"

  post "/activateEmail":
    createTFD()
    cond(@"nick" != "")
    cond(@"epoch" != "")
    cond(@"ident" != "")
    let epoch = getInt64(@"epoch", -1)
    try:
      verifyIdentHash(c, @"nick", epoch, @"ident")

      exec(
        db,
        sql"""
          update person set status = ?, lastOnline = DATETIME('now')
          where name = ?;
        """,
        $Rank.Moderated, @"nick"
      )
      resp Http200, "{}", "application/json"
    except ForumError as exc:
      resp Http400, $(%exc.data),"application/json"

  get "/t/@id":
    cond "id" in request.params

    const threadsQuery =
      sql"""select id from thread where id = ? and isDeleted = 0;"""

    let value = getValue(db, threadsQuery, @"id")
    if value == @"id":
      pass
    else:
      redirect uri("/404")

  get "/t/@id/@page":
    redirect uri("/t/" & @"id")

  get "/profile/@username":
    cond "username" in request.params

    const threadsQuery =
      sql"""select name from person where name = ? and isDeleted = 0;"""

    let value = getValue(db, threadsQuery, @"username")
    if value == @"username":
      pass
    else:
      redirect uri("/404")

  get "/404":
    resp Http404, readFile("public/karax.html")

  get "/about/license.html":
    let content = readFile("public/license.rst") %
      {
        "hostname": config.hostname,
        "name": config.name
      }.newStringTable()
    resp content.rstToHtml()

  get "/threadActivity.xml":
    createTFD()
    resp genThreadsRSS(c), "application/atom+xml"

  get "/postActivity.xml":
    createTFD()
    resp genPostsRSS(c), "application/atom+xml"

  get "/search.json":
    cond "q" in request.params
    let q = @"q"
    cond q.len > 0

    var results: seq[SearchResult] = @[]

    const queryFT = "fts.sql".slurp.sql
    const count = 40
    let data = [
      q, q, $count, $0, q,
      q, $count, $0, q
    ]
    for rowFT in fastRows(db, queryFT, data):
      var content = rowFT[3]
      try: content = content.rstToHtml() except EParseError: discard
      results.add(
        SearchResult(
          kind: SearchResultKind(rowFT[^1].parseInt()),
          threadId: rowFT[0].parseInt(),
          threadTitle: rowFT[1],
          postId: rowFT[2].parseInt(),
          postContent: content,
          creation: rowFT[4].parseInt(),
          author: selectUser(rowFT[5 .. 9]),
        )
      )

    resp Http200, $(%results), "application/json"

  get re"/(.*)":
    cond request.matches[0].splitFile.ext == ""
    resp karaxHtml