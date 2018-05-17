#
#
#              The Nim Forum
#        (c) Copyright 2012 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#

import
  os, strutils, times, md5, strtabs, math, db_sqlite,
  scgi, jester, asyncdispatch, asyncnet, sequtils,
  parseutils, utils, random, rst, recaptcha, json, re, sugar
import cgi except setCookie
import options

import auth

import frontend/threadlist except User
import frontend/[
  category, postlist, error, header, post, profile, user, karaxutils
]

when not defined(windows):
  import bcrypt # TODO

from htmlgen import tr, th, td, span, input

const
  unselectedThread = -1
  transientThread = 0

  ThreadsPerPage = 15
  PostsPerPage = 10
  MaxPagesFromCurrent = 8
  noPageNums = ["/login", "/register", "/dologin", "/doregister", "/profile"]
  noHomeBtn = ["/", "/login", "/register", "/dologin", "/doregister", "/profile"]

type
  TCrud = enum crCreate, crRead, crUpdate, crDelete

  TSession = object of RootObj
    threadid: int
    postid: int
    userName, userPass, email: string
    rank: Rank

  TPost = tuple[subject, content: string]

  TForumData = ref object of TSession
    req: Request
    userid: string
    actionContent: string
    errorMsg, loginErrorMsg: string
    invalidField: string
    currentPost: TPost ## Only used for reply previews
    startTime: float
    isThreadsList: bool
    pageNum: int
    totalPosts: int
    search: string
    noPagenumumNav: bool
    config: Config

  TStyledButton = tuple[text: string, link: string]

  TForumStats = object
    totalUsers: int
    totalPosts: int
    totalThreads: int
    newestMember: tuple[nick: string, id: int]
    activeUsers: seq[tuple[nick: string, id: int]]

  TUserInfo = object
    nick: string
    posts: int
    threads: int
    lastOnline: int
    email: string
    ban: string
    rank: Rank
    lastIp: string

  ForumError = object of Exception
    data: PostError

var
  db: DbConn
  isFTSAvailable: bool
  config: Config
  captcha: ReCaptcha

proc newForumError(message: string,
                   fields: seq[string] = @[]): ref ForumError =
  new(result)
  result.msg = message
  result.data =
    PostError(
      errorFields: fields,
      message: message
    )

proc init(c: TForumData) =
  c.userPass = ""
  c.userName = ""
  c.threadId = unselectedThread
  c.postId = -1

  c.userid = ""
  c.actionContent = ""
  c.errorMsg = ""
  c.loginErrorMsg = ""
  c.invalidField = ""
  c.currentPost = (subject: "", content: "")

  c.search = ""

proc loggedIn(c: TForumData): bool =
  result = c.userName.len > 0

# --------------- HTML widgets ------------------------------------------------

# for widgets "" means the empty string as usual; should the old value be
# used again, pass `reuseText` instead:
const
  reuseText = "\1"

proc textWidget(c: TForumData, name, defaultText: string,
                maxlength = 30, size = -1): string =
  let x = if defaultText != reuseText: defaultText
          else: xmlEncode(c.req.params.getOrDefault(name))
  return """<input type="text" name="$1" maxlength="$2" value="$3" $4/>""" % [
    name, $maxlength, x, if size != -1: "size=\"" & $size & "\"" else: ""]

proc hiddenField(c: TForumData, name, defaultText: string): string =
  let x = xmlencode(
            if defaultText != reuseText: defaultText
            else: c.req.params.getOrDefault(name)
          )
  return """<input type="hidden" name="$1" value="$2"/>""" % [name, x]

proc textAreaWidget(c: TForumData, name, defaultText: string): string =
  let x = if defaultText != reuseText: defaultText
          else: xmlEncode(c.req.params.getOrDefault(name))
  return """<textarea name="$1">$2</textarea>""" % [
    name, x]

proc fieldValid(c: TForumData, name, text: string): string =
  if name == c.invalidField:
    result = """<span style="color:red">$1</span>""" % text
  else:
    result = text

proc genThreadUrl(c: TForumData, postId = "", action = "", threadid = "", pageNum = ""): string =
  result = "/t/" & (if threadid == "": $c.threadId else: threadid)
  if pageNum != "":
    result.add("/" & pageNum)
  if action != "":
    result.add("?action=" & action)
    if postId != "":
      result.add("&postid=" & postid)
  elif postId != "":
    result.add("#" & postId)
  result = c.req.makeUri(result, absolute = false)

proc formSession(c: TForumData, nextAction: string): string =
  return """<input type="hidden" name="threadid" value="$1" />
            <input type="hidden" name="postid" value="$2" />""" % [
    $c.threadId, $c.postid]

proc urlButton(c: TForumData, text, url: string): string =
  return ("""<a class="url_button" href="$1">$2</a>""") % [
    url, text]

proc genButtons(c: TForumData, btns: seq[TStyledButton]): string =
  if btns.len == 1:
    var anchor = ""

    result = ("""<a class="active button" href="$1$3">$2</a>""") % [
      btns[0].link, btns[0].text, anchor]
  else:
    result = ""
    for i, btn in pairs(btns):
      var anchor = ""

      var class = ""
      if i == 0: class = "left "
      elif i == btns.len()-1: class = "right "
      else: class = "middle "
      result.add(("""<a class="$3active button" href="$1$4">$2</a>""") % [
        btns[i].link, btns[i].text, class, anchor])

proc toInterval(diff: int64): TimeInterval =
  var remaining = diff
  let years = remaining div 31536000
  remaining -= years * 31536000
  let months = remaining div 2592000
  remaining -= months * 2592000
  let days = remaining div 86400
  remaining -= days * 86400
  let hours = remaining div 3600
  remaining -= hours * 3600
  let minutes = remaining div 60
  remaining -= minutes * 60
  result = initInterval(remaining.int, minutes.int, hours.int, days.int,
                        months.int, years.int)

proc formatTimestamp(t: int): string =
  let t2 = fromUnix(t)
  let now = getTime()
  # let diff = (now - t2).toInterval()
  # if diff.years > 0:
  #   return getGMTime(t2).format("MMMM d',' yyyy")
  # elif diff.months > 0:
  #   return $diff.months & (if diff.months > 1: " months ago" else: " month ago")
  # elif diff.days > 0:
  #   return $diff.days & (if diff.days > 1: " days ago" else: " day ago")
  # elif diff.hours > 0:
  #   return $diff.hours & (if diff.hours > 1: " hours ago" else: " hour ago")
  # elif diff.minutes > 0:
  #   return $diff.minutes &
  #       (if diff.minutes > 1: " minutes ago" else: " minute ago")
  # else:
  return "just now"

proc getGravatarUrl(email: string, size = 80): string =
  let emailMD5 = email.toLowerAscii.toMD5
  return ("https://www.gravatar.com/avatar/" & $emailMD5 & "?s=" & $size &
     "&d=identicon")

proc genGravatar(email: string, size: int = 80): string =
  result = "<img width=\"$1\" height=\"$2\" src=\"$3\" />" %
            [$size, $size, getGravatarUrl(email, size)]



# -----------------------------------------------------------------------------
template `||`(x: untyped): untyped = (if not isNil(x): x else: "")

proc validThreadId(c: TForumData): bool =
  result = getValue(db, sql"select id from thread where id = ?",
                    $c.threadId).len > 0

proc setError(c: TForumData, field, msg: string): bool {.inline.} =
  c.invalidField = field
  c.errorMsg = "Error: " & msg
  return false

proc resetPassword(c: TForumData, nick, antibot, userIp: string): Future[bool] {.async.} =
  # captcha validation:
  if config.recaptchaSecretKey.len > 0:
    var captchaValid: bool = false
    try:
      captchaValid = await captcha.verify(antibot, userIp)
    except:
      echo("[ERROR] Error checking captcha: " & getCurrentExceptionMsg())
      captchaValid = false

    if not captchaValid:
      return setError(c, "g-recaptcha-response", "Answer to captcha incorrect!")

  # Gather some extra information to determine ident hash.
  let epoch = $int(epochTime())
  let row = db.getRow(
      sql"select password, salt, email from person where name = ?", nick)
  if row[0] == "":
    return setError(c, "nick", "Nickname not found")
  # Generate URL for the email.
  # TODO: Get rid of the stupid `%` in main.tmpl as it screws up strutils.%
  let resetUrl = c.req.makeUri(
      strutils.`%`("/emailResetPassword?nick=$1&epoch=$2&ident=$3",
          [encodeUrl(nick), encodeUrl(epoch),
           encodeUrl(makeIdentHash(nick, row[0], epoch, row[1]))]))
  echo "User's reset URL is: ", resetUrl
  # Send the email.
  let emailSentFut = sendPassReset(c.config, row[2], nick, resetUrl)
  # TODO: This is a workaround for 'var T' not being usable in async procs.
  while not emailSentFut.finished:
    poll()
  if emailSentFut.failed:
    echo("[WARNING] Couldn't send activation email: ", emailSentFut.error.msg)
    return setError(c, "email", "Couldn't send activation email")

  return true

proc logout(c: TForumData) =
  const query = sql"delete from session where ip = ? and password = ?"
  c.username = ""
  c.userpass = ""
  exec(db, query, c.req.ip, c.req.cookies["sid"])

proc getBanErrorMsg(banValue: string; rank: Rank): string =
  if banValue.len > 0:
    return "You have been banned: " & banValue
  case rank
  of Spammer, Troll, Banned: return "You have been banned."
  of EmailUnconfirmed:
    return "You need to confirm your email first."
  of Moderated, Rank.User, Moderator, Admin:
    return ""

proc checkLoggedIn(c: TForumData) =
  if not c.req.cookies.hasKey("sid"): return
  let pass = c.req.cookies["sid"]
  if execAffectedRows(db,
       sql("update session set lastModified = DATETIME('now') " &
           "where ip = ? and password = ?"),
           c.req.ip, pass) > 0:
    c.userpass = pass
    c.userid = getValue(db,
      sql"select userid from session where ip = ? and password = ?",
      c.req.ip, pass)

    let row = getRow(db,
      sql"select name, email, status from person where id = ?", c.userid)
    c.username = ||row[0]
    c.email = ||row[1]
    c.rank = parseEnum[Rank](||row[2])

    # Update lastOnline
    db.exec(sql"update person set lastOnline = DATETIME('now') where id = ?",
            c.userid)

  else:
    echo("SID not found in sessions. Assuming logged out.")

proc incrementViews(c: TForumData) =
  const query = sql"update thread set views = views + 1 where id = ?"
  exec(db, query, $c.threadId)

proc isPreview(c: TForumData): bool =
  result = c.req.params.hasKey("previewBtn")

proc isDelete(c: TForumData): bool =
  result = c.req.params.hasKey("delete")

proc validateRst(c: TForumData, content: string): bool =
  result = true
  try:
    discard rstToHtml(content)
  except EParseError:
    result = setError(c, "", getCurrentExceptionMsg())

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

template retrSubject(c: untyped) =
  if not c.req.params.hasKey("subject"):
    raise newException(ForumError, "Subject empty")
  let subject {.inject.} = c.req.params["subject"]
  if subject.strip.len < 3:
    return setError(c, "subject", "Subject not long enough")

template retrContent(c: untyped) =
  if not c.req.params.hasKey("content"):
    raise newException(ForumError, "Content empty")
  let content {.inject.} = c.req.params["content"]
  if content.strip.len < 2:
    return setError(c, "content", "Content not long enough")

  if not validateRst(c, content): return false

template retrPost(c: untyped) =
  retrSubject(c)
  retrContent(c)

template checkLogin(c: untyped) =
  if not loggedIn(c): return setError(c, "", "User is not logged in")

template checkOwnership(c, postId: untyped) =
  if c.rank < Moderator:
    let x = getValue(db, sql"select author from post where id = ?",
                     postId)
    if x != c.userId:
      return setError(c, "", "You are not the owner of this post")

template setPreviewData(c: untyped) {.dirty.} =
  c.currentPost.subject = subject
  c.currentPost.content = content

template writeToDb(c, cr, setPostId: untyped) =
  # insert a comment in the DB
  let retID = insertID(db, crud(cr, "post", "author", "ip", "header", "content", "thread"),
       c.userId, c.req.ip, subject, content, $c.threadId, "")
  discard tryExec(db, crud(cr, "post_fts", "id", "header", "content"),
       retID.int, subject, content)
  if setPostId:
    c.postId = retID.int

proc updateThreads(c: TForumData): int =
  ## Removes threads if they have no posts, or changes their modified field
  ## if they still contain posts.
  const query =
      sql"delete from thread where id not in (select thread from post)"
  result = execAffectedRows(db, query).int
  if result > 0:
    discard tryExec(db, sql"delete from thread_fts where id not in (select thread from post)")
  else:
    # Update corresponding thread's modified field.
    let getModifiedSql = "(select creation from post where post.thread = ?" &
        " order by creation desc limit 1)"
    let updateSql = sql("update thread set modified=" & getModifiedSql &
        " where id = ?")
    if not tryExec(db, updateSql, $c.threadId, $c.threadId):
      result = -1
      discard setError(c, "", "database error")

proc edit(c: TForumData, postId: int): bool =
  checkLogin(c)
  if c.isPreview:
    retrPost(c)
    setPreviewData(c)
  elif c.isDelete:
    checkOwnership(c, $postId)
    if not tryExec(db, crud(crDelete, "post"), $postId):
      return setError(c, "", "database error")
    discard tryExec(db, crud(crDelete, "post_fts"), $postId)
    result = true
    # delete corresponding thread:
    let updateResult = updateThreads(c)
    if updateResult > 0:
      # whole thread has been deleted, so:
      c.threadId = unselectedThread
    elif updateResult < 0:
      # error occurred
      return false
  else:
    checkOwnership(c, $postId)
    retrPost(c)
    exec(db, crud(crUpdate, "post", "header", "content"),
         subject, content, $postId)
    exec(db, crud(crUpdate, "post_fts", "header", "content"),
         subject, content, $postId)
    # Check if post is the first post of the thread.
    let rows = db.getAllRows(sql("select id, thread, creation from post " &
        "where thread = ? order by creation asc"), $c.threadId)
    if rows[0][0] == $postId:
      exec(db, crud(crUpdate, "thread", "name"), subject, $c.threadId)
    result = true

proc gatherUserInfo(c: TForumData, nick: string, ui: var TUserInfo): bool
proc spamCheck(c: TForumData, subject, content: string): bool =
  # Check current user's info
  var ui: TUserInfo
  if gatherUserInfo(c, c.userName, ui):
    if ui.posts > 1: return

  # Strip all punctuation
  var subjAlphabet = ""
  for i in subject:
    if i in Letters:
      subjAlphabet.add(i)
    case i
    of '!':
      subjAlphabet.add("i")
    else: discard
  var contentAlphabet = ""
  for i in content:
    if i in Letters:
      contentAlphabet.add(i)
    case i
    of '!':
      subjAlphabet.add("i")
    else: discard

  for word in ["appliance", "kitchen", "cheap", "sale", "relocating",
               "packers", "lenders", "fifa", "coins"]:
    if word in subjAlphabet.toLowerAscii() or
       word in contentAlphabet.toLowerAscii():
      return true

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

proc makeThreadURL(c: TForumData): string =
  c.req.makeUri("/t/" & $c.threadId)

template postChecks() {.dirty.} =
  if spamCheck(c, subject, content):
    echo("[WARNING] Found spam: ", subject)
    return true
  if rateLimitCheck(c):
    return setError(c, "subject", "You're posting too fast.")

proc reply(c: TForumData): bool =
  # reply to an existing thread
  checkLogin(c)
  retrPost(c)
  if c.isPreview:
    setPreviewData(c)
  else:
    postChecks()
    writeToDb(c, crCreate, true)

    exec(db, sql"update thread set modified = DATETIME('now') where id = ?",
         $c.threadId)
    if c.rank >= Rank.User:
      asyncCheck sendMailToMailingList(c.config, c.username, c.email,
          subject, content, threadId=c.threadId, postId=c.postID, is_reply=true,
          threadUrl=c.makeThreadURL())
    result = true

proc newThread(c: TForumData): bool =
  # create new conversation thread (permanent or transient)
  const query = sql"insert into thread(name, views, modified) values (?, 0, DATETIME('now'))"
  checkLogin(c)
  retrPost(c)
  if c.isPreview:
    setPreviewData(c)
    c.threadID = transientThread
  else:
    postChecks()
    c.threadID = tryInsertID(db, query, c.req.params["subject"]).int
    if c.threadID < 0: return setError(c, "subject", "Subject already exists")
    discard tryExec(db, crud(crCreate, "thread_fts", "id", "name"),
                        c.threadID, c.req.params["subject"])
    writeToDb(c, crCreate, false)
    discard tryExec(db, sql"insert into post_fts(post_fts) values('optimize')")
    discard tryExec(db, sql"insert into post_fts(thread_fts) values('optimize')")
    if c.rank >= Rank.User:
      asyncCheck sendMailToMailingList(c.config, c.username, c.email,
          subject, content, threadId=c.threadID, postId=c.postID, is_reply=false,
          threadUrl=c.makeThreadURL())
    result = true

proc verifyIdentHash(c: TForumData, name, epoch, ident: string): bool =
  const query =
    sql"select password, salt, strftime('%s', lastOnline) from person where name = ?"
  var row = getRow(db, query, name)
  if row[0] == "": return false
  let newIdent = makeIdentHash(name, row[0], epoch, row[1], ident)
  # Check that the user has not been logged in since this ident hash has been
  # created. Give the timestamp a certain range to prevent false negatives.
  if row[2].parseInt > (epoch.parseInt + 60): return false
  result = newIdent == ident

proc deleteAll(c: TForumData, nick: string): bool =
  const query =
    sql("delete from post where author = (select id from person where name = ?)")
  result = tryExec(db, query, nick)
  result = result and updateThreads(c) >= 0

proc setStatus(c: TForumData, nick: string, status: Rank;
               reason: string): bool =
  const query =
    sql("update person set status = ?, ban = ? where name = ?")
  result = tryExec(db, query, $status, reason, nick)
  when false:
    # for now we filter Spammers in forms.tmpl, so that a moderator
    # cannot accidentically delete all of a user's posts. We go even
    # further than that and show spammers their own spam postings.
    if status == Spammer and result:
      result = deleteAll(c, nick)

proc setPassword(c: TForumData, nick, pass: string): bool =
  const query =
    sql("update person set password = ?, salt = ? where name = ?")
  var salt = makeSalt()
  result = tryExec(db, query, makePassword(pass, salt), salt, nick)

proc hasReplyBtn(c: TForumData): bool =
  result = c.req.pathInfo != "/donewthread" and c.req.pathInfo != "/doreply"
  result = result and c.req.params.getOrDefault("action") notin ["reply", "edit"]
  # If the user is not logged in and there are no page numbers then we shouldn't
  # generate the div.
  let pages = ceil(c.totalPosts / PostsPerPage).int
  result = result and (pages > 1 or c.loggedIn)
  return c.threadId >= 0 and result

proc getStats(c: TForumData, simple: bool): TForumStats =
  const totalUsersQuery =
    sql"select count(*) from person"
  result.totalUsers = getValue(db, totalUsersQuery).parseInt
  const totalPostsQuery =
    sql"select count(*) from post"
  result.totalPosts = getValue(db, totalPostsQuery).parseInt
  const totalThreadsQuery =
    sql"select count(*) from thread"
  result.totalThreads = getValue(db, totalThreadsQuery).parseInt
  if not simple:
    var newestMemberCreation = 0
    result.activeUsers = @[]
    result.newestMember = ("", -1)
    const getUsersQuery =
      sql"select id, name, strftime('%s', lastOnline), strftime('%s', creation) from person"
    for row in fastRows(db, getUsersQuery):
      let secs = if row[3] == "": 0 else: row[3].parseint
      when false:
        let lastOnlineSeconds = getTime() - Time(secs)
        if lastOnlineSeconds < (60 * 5): # 5 minutes
          result.activeUsers.add((row[1], row[0].parseInt))
      if row[3].parseInt > newestMemberCreation:
        result.newestMember = (row[1], row[0].parseInt)
        newestMemberCreation = row[3].parseInt

proc genPagenumNav(c: TForumData, stats: TForumStats): string =
  result = ""
  var
    firstUrl = ""
    prevUrl  = ""
    totalPages = 0
    lastUrl = ""
    nextUrl = ""

  if c.isThreadsList:
    firstUrl = c.req.makeUri("/")
    prevUrl = c.req.makeUri(if c.pageNum == 1: "/" else: "/page/" & $(c.pageNum-1))
    totalPages = ceil(stats.totalThreads / ThreadsPerPage).int
    lastUrl = c.req.makeUri("/page/" & $(totalPages))
    nextUrl = c.req.makeUri("/page/" & $(c.pageNum+1))
  else:
    firstUrl = c.makeThreadURL()
    if c.pageNum == 1:
      prevUrl = firstUrl
    else:
      prevUrl = c.req.makeUri(firstUrl & "/" & $(c.pageNum-1))
    totalPages = ceil(c.totalPosts / PostsPerPage).int
    lastUrl = c.req.makeUri(firstUrl & "/" & $(totalPages))
    nextUrl = c.req.makeUri(firstUrl & "/" & $(c.pageNum+1))

  if totalPages <= 1:
    return ""

  var firstTag = ""
  var prevTag = ""
  if c.pageNum == 1:
    firstTag = span("<<")
    prevTag = span("<••")
  else:
    firstTag = htmlgen.a(href=firstUrl, "<<")
    prevTag = htmlgen.a(href=prevUrl, "<••")
    prevTag.add(htmlgen.link(rel="previous", href=prevUrl))
  result.add(firstTag)
  result.add(prevTag)

  # Numbers
  var pages = "" # Tags
  # cutting numbers to the left and to the right tp MaxPagesFromCurrent
  let firstToShow = max(1, c.pageNum - MaxPagesFromCurrent)
  let lastToShow  = min(totalPages, c.pageNum + MaxPagesFromCurrent)
  if firstToShow > 1: pages.add(span("..."))
  for i in firstToShow .. lastToShow:
    if i == c.pageNum:
      pages.add(span($(i)))
    else:
      var pageUrl = ""
      if c.isThreadsList:
        pageUrl = c.req.makeUri("/page/" & $(i))
      else:
        pageUrl = c.req.makeUri(firstUrl & "/" & $(i))

      pages.add(htmlgen.a(href = pageUrl, $(i)))
  if lastToShow < totalPages: pages.add(span("..."))
  result.add(pages)

  # Right
  var lastTag = ""
  var nextTag = ""
  if c.pageNum == totalPages:
    lastTag = span(">>")
    nextTag = span("••>")
  else:
    lastTag = htmlgen.a(href=lastUrl, ">>")
    nextTag = htmlgen.a(href=nextUrl, "••>")
    nextTag.add(htmlgen.link(rel="next",href=nextUrl))
  result.add(nextTag)
  result.add(lastTag)

proc gatherTotalPostsByID(c: TForumData, thrid: int): int =
  ## Gets the total post count of a thread.
  result = getValue(db, sql"select count(*) from post where thread = ?", $thrid).parseInt

proc gatherTotalPosts(c: TForumData) =
  if c.totalPosts > 0: return
  # Gather some data.
  const totalPostsQuery =
      sql"select count(*) from post p, person u where u.id = p.author and p.thread = ?"
  c.totalPosts = getValue(db, totalPostsQuery, $c.threadId).parseInt

proc getPagesInThread(c: TForumData): int =
  c.gatherTotalPosts() # Get total post count
  result = ceil(c.totalPosts / PostsPerPage).int-1

proc getPagesInThreadByID(c: TForumData, thrid: int): int =
  result = ceil(c.gatherTotalPostsByID(thrid) / PostsPerPage).int

proc getThreadTitle(thrid: int, pageNum: int): string =
  echo thrid
  result = getValue(db, sql"select name from thread where id = ?", $thrid)
  if pageNum notin {0,1}:
    result.add(" - Page " & $pageNum)

proc genPagenumLocalNav(c: TForumData, thrid: int): string =
  result = ""
  const maxPostPages = 6 # Maximum links to pages shown.
  const hmpp = maxPostPages div 2
  # 1 2 3 ... 10 11 12
  var currentThrURL = "/t/" & $thrid & "/"
  let totalPagesInThread = c.getPagesInThreadByID(thrid)
  if totalPagesInThread <= 1: return
  var i = 1
  while i <= totalPagesInThread:
    result.add(htmlgen.a(href=c.req.makeUri(currentThrURL & $i), $i))
    if i == hmpp and totalPagesInThread-i > hmpp:
      result.add(span("..."))
      # skip to the last 3
      i = totalPagesInThread-(hmpp-1)
    else:
      inc(i)

  result = htmlgen.span(class = "pages", result)

proc gatherUserInfo(c: TForumData, nick: string, ui: var TUserInfo): bool =
  ui.nick = nick
  const getUIDQuery = sql"select id from person where name = ?"
  var uid = getValue(db, getUIDQuery, nick)
  if uid == "": return false
  result = true
  const totalPostsQuery =
      sql"select count(*) from post where author = ?"
  ui.posts = getValue(db, totalPostsQuery, uid).parseInt
  const totalThreadsQuery =
      sql("select count(*) from thread where id in (select thread from post where" &
         " author = ? and post.id in (select min(id) from post group by thread))")

  ui.threads = getValue(db, totalThreadsQuery, uid).parseInt
  const lastOnlineQuery =
      sql"""select strftime('%s', lastOnline), email, ban, status
            from person where id = ?"""
  let row = db.getRow(lastOnlineQuery, $uid)
  ui.lastOnline = if row[0].len > 0: row[0].parseInt else: -1
  ui.email = row[1]
  ui.ban = row[2]
  ui.rank = parseEnum[Rank](row[3])

  const lastIpQuery = sql"select `ip` from `session` where `userid` = ? order by `id` desc limit 1;"
  let ipRow = db.getRow(lastIpQuery, $uid)
  ui.lastIp = ipRow[0]

include "forms.tmpl"
include "main.tmpl"

proc genProfile(c: TForumData, ui: TUserInfo): string =
  result = ""

  result.add(htmlgen.`div`(id = "talk-head",
    htmlgen.`div`(class="info-post",
      htmlgen.`div`(
        htmlgen.a(href = c.req.makeUri("/"),
          span(style = "font-weight: bold;", "forum index")
          ),
          " > " & ui.nick & "'s profile"
        )
      )
    )
  )
  result.add(htmlgen.`div`(id = "avatar", genGravatar(ui.email, 250)))
  let t2 = if ui.lastOnline != -1: getGMTime(fromUnix(ui.lastOnline))
           else: getGMTime(getTime())

  result.add(htmlgen.`div`(id = "info",
    htmlgen.table(
      tr(
        th("Nickname"),
        td(ui.nick)
      ),
      tr(
        th("Threads"),
        td($ui.threads)
      ),
      tr(
        th("Posts"),
        td($ui.posts)
      ),
      tr(
        th("Last Online"),
        td(if ui.lastOnline != -1: t2.format("dd/MM/yy HH':'mm 'UTC'")
           else: "Never")
      ),
      tr(
        th("Status"),
        td($ui.rank)
      ),
      tr(
        th(if c.rank >= Moderator: "Last IP" else: ""),
        td(if c.rank >= Moderator:
             htmlgen.a(href="http://whatismyipaddress.com/ip/" & encodeUrl(ui.lastIp), ui.lastIp)
           else: "")
      ),
      tr(
        th(""),
        td(if c.rank >= Moderator and c.rank > ui.rank:
             c.genFormSetRank(ui)
           else: "")
      ),
      tr(
        th(""),
        td(if c.rank >= Moderator:
             htmlgen.a(href=c.req.makeUri("/deleteAll?nick=$1" % ui.nick),
                     "Delete all user's posts and threads")
           else: "")
      ),
    )
  ))

  result = htmlgen.`div`(id = "profile",
    htmlgen.`div`(id = "left", result))

proc prependRe(s: string): string =
  result = if s.len == 0:
             ""
           elif s.startswith("Re:"): s
           else: "Re: " & s

proc initialise() =
  randomize()
  db = open(connection="nimforum.db", user="postgres", password="",
              database="nimforum")
  isFTSAvailable = db.getAllRows(sql("SELECT name FROM sqlite_master WHERE " &
      "type='table' AND name='post_fts'")).len == 1

  config = loadConfig()
  if len(config.recaptchaSecretKey) > 0 and len(config.recaptchaSiteKey) > 0:
    captcha = initReCaptcha(config.recaptchaSecretKey, config.recaptchaSiteKey)
  else:
    doAssert config.isDev, "Recaptcha required for production!"
    echo("[WARNING] No recaptcha secret key specified.")

template createTFD() =
  var c {.inject.}: TForumData
  new(c)
  init(c)
  c.req = request
  c.startTime = epochTime()
  c.isThreadsList = false
  c.pageNum = 1
  c.config = config
  if request.cookies.len > 0:
    checkLoggedIn(c)

#[ DB functions. TODO: Move to another module? ]#

proc selectUser(userRow: seq[string], avatarSize: int=80): User =
  return User(
    name: userRow[0],
    avatarUrl: userRow[1].getGravatarUrl(avatarSize),
    lastOnline: userRow[2].parseInt,
    rank: parseEnum[Rank](userRow[3])
  )

proc selectPost(postRow: seq[string], skippedPosts: seq[int],
                replyingTo: Option[PostLink]): Post =
  return Post(
    id: postRow[0].parseInt,
    replyingTo: replyingTo,
    author: selectUser(@[postRow[5], postRow[6], postRow[7], postRow[8]]),
    likes: @[], # TODO:
    seen: false, # TODO:
    history: @[], # TODO:
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
    author: some(selectUser(@[row[3], row[4], row[5], row[6]]))
  ))

proc selectThread(threadRow: seq[string]): Thread =
  const postsQuery =
    sql"""select count(*), strftime('%s', creation) from post
          where thread = ?
          order by creation asc limit 1;"""
  const usersListQuery =
    sql"""
      select name, email, strftime('%s', lastOnline), status, count(*)
      from person u, post p where p.author = u.id and p.thread = ?
      group by name order by count(*) desc limit 5;
    """
  const authorQuery =
    sql"""
      select name, email, strftime('%s', lastOnline), status
      from person where id in (
        select author from post
        where thread = ?
        order by id
        limit 1
      )
    """

  let posts = getRow(db, postsQuery, threadRow[0])

  var thread = Thread(
    id: threadRow[0].parseInt,
    topic: threadRow[1],
    category: Category(id: "", color: "#ff0000"), # TODO
    users: @[],
    replies: posts[0].parseInt-1,
    views: threadRow[2].parseInt,
    activity: threadRow[3].parseInt,
    creation: posts[1].parseInt,
    isLocked: false, # TODO:
    isSolved: false, # TODO: Add a field to `post` to identify the solution.
    isDeleted: false # TODO:
  )

  # Gather the users list.
  for user in getAllRows(db, usersListQuery, thread.id):
    thread.users.add(selectUser(user))

  # Grab the author.
  thread.author = selectUser(getRow(db, authorQuery, thread.id))

  return thread

proc executeReply(c: TForumData, threadId: int, content: string,
                  replyingTo: Option[int]): int64 =
  # TODO: Refactor TForumData.
  assert c.loggedIn()

  if rateLimitCheck(c):
    raise newForumError("You're posting too fast!")

  if not validateRst(c, content):
    raise newForumError("Message needs to be valid RST", @["msg"])

  # Verify that content can be parsed as RST.
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
  let canEdit = c.rank == Admin or c.username == postRow[0]
  if isArchived:
    raise newForumError("This post is archived and can no longer be edited")
  if not canEdit:
    raise newForumError("You cannot edit this post")

  if not validateRst(c, content):
    raise newForumError("Message needs to be valid RST", @["msg"])

  # Update post.
  exec(db, crud(crUpdate, "post", "content"), content, $postId)
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
                      c.threadID, subject)
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
      from person where name = ? or email = ?
    """
  if username.len == 0:
    raise newForumError("Username cannot be empty", @["username"])

  for row in fastRows(db, query, username, username):
    if row[2] == makePassword(password, row[4], row[2]):
      exec(
        db,
        sql"insert into session (ip, password, userid) values (?, ?, ?)",
        c.req.ip, row[2], row[0]
      )
      return row[2]

  raise newForumError("Invalid username or password")

proc executeRegister(c: TForumData, name, pass, antibot, userIp,
                     email: string): Future[string] {.async.} =
  ## Registers a new user and returns a new session key for that user's
  ## session if registration was successful. Exceptions are raised otherwise.

  # email validation
  if not ('@' in email and '.' in email):
    raise newForumError("Invalid email", @["email"])
  if getValue(
      db, sql"select email from person where email = ?", email
  ).len > 0:
    raise newForumError("Email already exists", @["email"])

  # Username validation:
  if name.len == 0 or not allCharsInSet(name, UsernameIdent):
    raise newForumError("Invalid username", @["username"])
  if getValue(db, sql"select name from person where name = ?", name).len > 0:
    raise newForumError("Username already exists", @["username"])

  # Password validation:
  if pass.len < 4:
    raise newForumError("Please choose a longer password", @["password"])

  # captcha validation:
  if config.recaptchaSecretKey.len > 0:
    var verifyFut = captcha.verify(antibot, userIp)
    yield verifyFut
    if verifyFut.failed:
      raise newForumError(
        "Invalid recaptcha answer", @[]
      )

  # perform registration:
  var salt = makeSalt()
  let password = makePassword(pass, salt)

  # Send activation email.
  let epoch = $int(epochTime())
  let activateUrl = c.req.makeUri("/activateEmail?nick=$1&epoch=$2&ident=$3" %
      [encodeUrl(name), encodeUrl(epoch),
       encodeUrl(makeIdentHash(name, password, epoch, salt))])

  let emailSentFut = sendEmailActivation(c.config, email, name, activateUrl)
  yield emailSentFut
  if emailSentFut.failed:
    echo("[WARNING] Couldn't send activation email: ", emailSentFut.error.msg)
    raise newForumError("Couldn't send activation email", @["email"])

  # Add account to person table
  exec(db,
    sql("INSERT INTO person(name, password, email, salt, status, lastOnline) " &
        "VALUES (?, ?, ?, ?, ?, DATETIME('now'))"), name,
              password, email, salt, $EmailUnconfirmed)

  return password

initialise()

routes:

  get "/nimforum.css":
    resp readFile("frontend/nimforum.css"), "text/css"
  get "/nimcache/forum.js":
    resp readFile("frontend/nimcache/forum.js"), "application/javascript"
  get re"/images/(.+?\.png)/?":
    let path = "frontend/images/" & request.matches[0]
    if fileExists(path):
      resp readFile(path), "image/png"
    else:
      resp Http404, "No such file."

  get "/threads.json":
    var
      start = getInt(@"start", 0)
      count = getInt(@"count", 30)

    const threadsQuery =
      sql"""select id, name, views, strftime('%s', modified) from thread
            where isDeleted = 0
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
      sql"""select id, name, views, strftime('%s', modified) from thread
            where id = ? and isDeleted = 0;"""

    let threadRow = getRow(db, threadsQuery, id)
    let thread = selectThread(threadRow)

    let postsQuery =
      sql(
        """select p.id, p.content, strftime('%s', p.creation), p.author,
                  p.replyingTo,
                  u.name, u.email, strftime('%s', u.lastOnline), u.status
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
        let post = selectPost(rows[i], skippedPosts, replyingTo)
        list.posts.add(post)
        skippedPosts = @[]
      else:
        skippedPosts.add(id)

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
             u.name, u.email, strftime('%s', u.lastOnline), u.status
      from post p, person u
      where u.id = p.author and p.id in ($#)
      order by p.id;
    """ % intIDs.join(",")) # TODO: It's horrible that I have to do this.

    var list: seq[Post] = @[]

    for row in db.getAllRows(postsQuery):
      list.add(selectPost(row, @[], selectReplyingTo(row[4])))

    resp $(%list), "application/json"

  get "/post.rst":
    createTFD()
    let postId = getInt(@"id", -1)
    cond postId != -1

    let postQuery = sql"""
      select content from post where id = ?;
    """

    let content = getValue(db, postQuery, postId)
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
      select name, email, strftime('%s', lastOnline), status,
             strftime('%s', creation), id
      from person
      where name = ?
    """)

    var profile = Profile(
      threads: @[],
      posts: @[]
    )

    let userRow = db.getRow(userQuery, username)

    let userID = userRow[^1]
    profile.user = selectUser(userRow, avatarSize=200)
    profile.joinTime = userRow[4].parseInt()
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
      discard await executeRegister(
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

  get "/t/@id":
    cond "id" in request.params

    const threadsQuery =
      sql"""select id from thread where id = ? and isDeleted = 0;"""

    let value = getValue(db, threadsQuery, @"id")
    if value == @"id":
      pass
    else:
      redirect uri("/404")

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
    resp Http404, readFile("frontend/karax.html")

  get re"/(.+)?":
    resp readFile("frontend/karax.html")

  get "/threadActivity.xml":
    createTFD()
    c.isThreadsList = true
    resp genThreadsRSS(c), "application/atom+xml"

  get "/postActivity.xml":
    createTFD()
    resp genPostsRSS(c), "application/atom+xml"

  get "/deleteAll/?":
    createTFD()
    cond(@"nick" != "")
    var formBody = "<input type=\"hidden\" name=\"nick\" value=\"" &
                      @"nick" & "\">"
    var del = false
    var content = ""
    formBody.add "<input type='submit' name='deleteAllBtn' value='Delete All' />"
    content = htmlgen.p("Are you sure you wish to delete all " &
      "the posts and threads created by ", htmlgen.b(@"nick"), "?")
    content = content & htmlgen.form(action = c.req.makeUri("/dodeleteall"),
        `method` = "POST", formBody)
    resp genMain(c, content, "Delete all user's posts & threads - Nim Forum")

  post "/dodeleteall/?":
    createTFD()
    cond(@"nick" != "")
    if c.rank < Moderator:
      resp genMain(c, "You cannot delete this user's data.", "Error - Nim Forum")
    let res = deleteAll(c, @"nick")
    if res:
      redirect(c.req.makeUri("/profile/" & @"nick"))
    else:
      resp genMain(c, "Failed to delete all user's posts and threads.",
          "Error - NimForum")

  post "/dosetrank/?@nick?/?":
    createTFD()
    cond(@"nick" != "")

    if c.rank < Moderator:
      resp genMain(c, "You cannot change this user's rank.", "Error - Nim Forum")

    var ui: TUserInfo
    if not gatherUserInfo(c, @"nick", ui):
      resp genMain(c, "User " & @"nick" & " does not exist.", "Error - Nim Forum")
    let newRank = parseEnum[Rank](@"rank")
    if newRank > c.rank:
      resp genMain(c, "You cannot change this user's rank to this value.", "Error - Nim Forum")

    if setStatus(c, @"nick", newRank, @"reason"):
      redirect(c.req.makeUri("/profile/" & @"nick"))
    else:
      resp genMain(c, "Failed to change the ban status of user.",
          "Error - Nim Forum")

  get "/setpassword/?":
    createTFD()
    cond(@"nick" != "")
    cond(@"pass" != "")
    if c.rank < Moderator:
      resp genMain(c, "You cannot change this user's pass.", "Error - Nim Forum")
    let res = setPassword(c, @"nick", @"pass")
    if res:
      resp genMain(c, "Success", "Nim Forum")
    else:
      resp genMain(c, "Failure", "Nim Forum")

  get "/activateEmail/?":
    createTFD()
    cond(@"nick" != "")
    cond(@"epoch" != "")
    cond(@"ident" != "")
    var epoch: BiggestInt = 0
    cond(parseBiggestInt(@"epoch", epoch) > 0)
    var success = false
    if verifyIdentHash(c, @"nick", $epoch, @"ident"):
      let ban = parseEnum[Rank](db.getValue(sql"select status from person where name = ?", @"nick"))
      if ban == EmailUnconfirmed:
        success = setStatus(c, @"nick", Moderated, "")

    if success:
      resp genMain(c, "Account activated", "Nim Forum")
    else:
      resp genMain(c, "Account activation failed", "Nim Forum")

  get "/emailResetPassword/?":
    createTFD()
    cond(@"nick" != "")
    cond(@"epoch" != "")
    cond(@"ident" != "")
    var epoch: BiggestInt = 0
    cond(parseBiggestInt(@"epoch", epoch) > 0)
    if verifyIdentHash(c, @"nick", $epoch, @"ident"):
      let formBody = input(`type`="hidden", name="nick", value = @"nick") &
                     input(`type`="hidden", name="epoch", value = @"epoch") &
                     input(`type`="hidden", name="ident", value = @"ident") &
                     input(`type`="password", name="password") &
                     "<br/>" &
                     input(`type`="submit", name="submitBtn",
                           value="Change my password")
      let message = htmlgen.p("Please enter a new password for ",
                              htmlgen.b(@"nick"), ':')
      let content = htmlgen.form(action=c.req.makeUri("/doemailresetpassword"),
                         `method`="POST", message & formBody)

      resp genMain(c, content, "Reset password - Nim Forum")
    else:
      resp genMain(c, "Invalid ident hash", "Error - Nim Forum")

  post "/doemailresetpassword":
    createTFD()
    cond(@"nick" != "")
    cond(@"epoch" != "")
    cond(@"ident" != "")
    cond(@"password" != "")
    var epoch: BiggestInt = 0
    cond(parseBiggestInt(@"epoch", epoch) > 0)
    if verifyIdentHash(c, @"nick", $epoch, @"ident"):
      let res = setPassword(c, @"nick", @"password")
      if res:
        resp genMain(c, "Password reset successfully!", "Nim Forum")
      else:
        resp genMain(c, "Password reset failure", "Nim Forum")
    else:
      resp genMain(c, "Invalid ident hash", "Nim Forum")

  get "/resetPassword/?":
    createTFD()

    resp genMain(c, genFormResetPassword(c), "Reset Password - Nim Forum")

  post "/doresetpassword":
    createTFD()
    echo(request.params)
    cond(@"nick" != "")

    if await resetPassword(c, @"nick", @"g-recaptcha-response", request.host):
      resp genMain(c, "Email sent!", "Reset Password - Nim Forum")
    else:
      resp genMain(c, genFormResetPassword(c), "Reset Password - Nim Forum")

  const licenseRst = slurp("static/license.rst")
  get "/license":
    createTFD()
    resp genMain(c, rstToHtml(licenseRst), "Content license - Nim Forum")

  post "/search/?@page?":
    cond isFTSAvailable
    createTFD()
    c.isThreadsList  = true
    c.noPagenumumNav = true
    var count = 0
    var q = @"q"
    for i in 0 .. q.len-1:
      if   q[i].int < 32: q[i] = ' '
      elif q[i] == '\'':  q[i] = '"'
    c.search = q.replace("\"","&quot;")
    if @"page".len > 0:
      parseInt(@"page", c.pageNum, 0..1000_000)
      cond(c.pageNum > 0)
    iterator searchResults(): db_sqlite.Row {.closure, tags: [ReadDbEffect].} =
      const queryFT = "fts.sql".slurp.sql
      for rowFT in fastRows(db, queryFT,
                    [q,q,$ThreadsPerPage,$c.pageNum,$ThreadsPerPage,q,
                     q,q,$ThreadsPerPage,$c.pageNum,$ThreadsPerPage,q]):
        yield rowFT
    resp genMain(c, genSearchResults(c, searchResults, count),
                 additionalHeaders = genRSSHeaders(c), showRssLinks = true)

  # tries first to read html, then to read rst, convert ot html, cache and return
  template textPage(path: string) =
    createTFD()
    #c.isThreadsList = true
    var page = ""
    if existsFile(path):
      page = readFile(path)
    else:
      let basePath =
        if path[path.high] == '/': path & "index"
        elif path.endsWith(".html"): path[^5 .. ^1]
        else: path
      if existsFile(basePath & ".html"):
        page = readFile(basePath & ".html")
      elif existsFile(basePath & ".rst"):
        page = readFile(basePath & ".rst").rstToHtml
        writeFile(basePath & ".html", page)
    resp genMain(c, page)
  get "/search-help":
    textPage "static/search-help"
  get "/rst":
    textPage "static/rst"
