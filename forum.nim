#
#
#              The Nim Forum
#        (c) Copyright 2012 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#

import
  os, strutils, times, md5, strtabs, cgi, math, db_sqlite, matchers,
  rst, rstgen, captchas, scgi, jester, asyncdispatch, asyncnet, cache, sequtils,
  parseutils, utils

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
  banReasonDeactivated = "DEACTIVATED"
  banReasonEmailUnconfirmed = "EMAILCONFIRMATION"

type
  TCrud = enum crCreate, crRead, crUpdate, crDelete

  TSession = object of RootObj
    threadid: int
    postid: int
    userName, userPass, email: string
    isAdmin: bool

  TPost = tuple[subject, content: string]

  TForumData = object of TSession
    req: PRequest
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
    newestMember: tuple[nick: string, id: int, isAdmin: bool]
    activeUsers: seq[tuple[nick: string, id: int, isAdmin: bool]]

  TUserInfo = object
    nick: string
    posts: int
    threads: int
    lastOnline: int
    email: string
    ban: string

var
  db: TDbConn
  docConfig: StringTableRef
  isFTSAvailable: bool
  config: Config

proc init(c: var TForumData) =
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

proc TextWidget(c: TForumData, name, defaultText: string,
                maxlength = 30, size = -1): string =
  let x = if defaultText != reuseText: defaultText
          else: xmlEncode(c.req.params[name])
  return """<input type="text" name="$1" maxlength="$2" value="$3" $4/>""" % [
    name, $maxlength, x, if size != -1: "size=\"" & $size & "\"" else: ""]

proc HiddenField(c: TForumData, name, defaultText: string): string =
  let x = if defaultText != reuseText: defaultText
          else: xmlEncode(c.req.params[name])
  return """<input type="hidden" name="$1" value="$2"/>""" % [name, x]

proc TextAreaWidget(c: TForumData, name, defaultText: string): string =
  let x = if defaultText != reuseText: defaultText
          else: xmlEncode(c.req.params[name])
  return """<textarea name="$1">$2</textarea>""" % [
    name, x]

proc FieldValid(c: TForumData, name, text: string): string =
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

proc FormSession(c: var TForumData, nextAction: string): string =
  return """<input type="hidden" name="threadid" value="$1" />
            <input type="hidden" name="postid" value="$2" />""" % [
    $c.threadId, $c.postid]

proc UrlButton(c: var TForumData, text, url: string): string =
  return ("""<a class="url_button" href="$1">$2</a>""") % [
    url, text]

proc genButtons(c: var TForumData, btns: seq[TStyledButton]): string =
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
  result = initInterval(0, remaining.int, minutes.int, hours.int, days.int,
                        months.int, years.int)

proc formatTimestamp(t: int): string =
  let t2 = Time(t)
  let now = getTime()
  let diff = (now - t2).toInterval()
  if diff.years > 0:
    return getGMTime(t2).format("MMMM d',' yyyy")
  elif diff.months > 0:
    return $diff.months & (if diff.months > 1: " months ago" else: " month ago")
  elif diff.days > 0:
    return $diff.days & (if diff.days > 1: " days ago" else: " day ago")
  elif diff.hours > 0:
    return $diff.hours & (if diff.hours > 1: " hours ago" else: " hour ago")
  elif diff.minutes > 0:
    return $diff.minutes &
        (if diff.minutes > 1: " minutes ago" else: " minute ago")
  else:
    return "just now"

proc getGravatarUrl(email: string, size = 80): string =
  let emailMD5 = email.toLower.toMD5
  return ("http://www.gravatar.com/avatar/" & $emailMD5 & "?s=" & $size &
     "&d=identicon")

proc genGravatar(email: string, size: int = 80): string =
  result = "<img width=\"$1\" height=\"$2\" src=\"$3\" />" %
            [$size, $size, getGravatarUrl(email, size)]

proc randomSalt(): string =
  result = ""
  for i in 0..127:
    var r = random(225)
    if r >= 32 and r <= 126:
      result.add(chr(random(225)))

proc devRandomSalt(): string =
  when defined(posix):
    result = ""
    var f = open("/dev/urandom")
    var randomBytes: array[0..127, char]
    discard f.readBuffer(addr(randomBytes), 128)
    for i in 0..127:
      if ord(randomBytes[i]) >= 32 and ord(randomBytes[i]) <= 126:
        result.add(randomBytes[i])
    f.close()
  else:
    result = randomSalt()

proc makeSalt(): string =
  ## Creates a salt using a cryptographically secure random number generator.
  ##
  ## Ensures that the resulting salt contains no ``\0``.
  try:
    result = devRandomSalt()
  except IOError:
    result = randomSalt()

  var newResult = ""
  for i in 0 .. <result.len:
    if result[i] != '\0':
      newResult.add result[i]
  return newResult

proc makePassword(password, salt: string, comparingTo = ""): string =
  ## Creates an MD5 hash by combining password and salt.
  when defined(windows):
    result = getMD5(salt & getMD5(password))
  else:
    let bcryptSalt = if comparingTo != "": comparingTo else: genSalt(8)
    result = hash(getMD5(salt & getMD5(password)), bcryptSalt)

proc makeIdentHash(user, password, epoch, secret: string,
                   comparingTo = ""): string =
  ## Creates a hash verifying the identity of a user. Used for password reset
  ## links and email activation links.
  ## If ``epoch`` is smaller than the epoch of the user's last login then
  ## the link is invalid.
  ## The ``secret`` is the 'salt' field in the ``person`` table.
  echo(user, password, epoch, secret)
  when defined(windows):
    result = getMD5(user & password & epoch & secret)
  else:
    let bcryptSalt = if comparingTo != "": comparingTo else: genSalt(8)
    result = hash(user & password & epoch & secret, bcryptSalt)

# -----------------------------------------------------------------------------
template `||`(x: expr): expr = (if not isNil(x): x else: "")

proc validThreadId(c: TForumData): bool =
  result = getValue(db, sql"select id from thread where id = ?",
                    $c.threadId).len > 0

proc antibot(c: var TForumData): string =
  let a = math.random(10)+1
  let b = math.random(1000)+1
  let answer = $(a+b)

  exec(db, sql"delete from antibot where ip = ?", c.req.ip)
  let captchaId = tryInsertID(db,
    sql"insert into antibot(ip, answer) values (?, ?)", c.req.ip,
    answer).int mod 10_000
  let captchaFile = getCaptchaFilename(captchaId)
  createCaptcha(captchaFile, $a & "+" & $b)
  result = """<img src="$1" />""" % c.req.getCaptchaUrl(captchaId)

const
  SecureChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '\128'..'\255'}

proc setError(c: var TForumData, field, msg: string): bool {.inline.} =
  c.invalidField = field
  c.errorMsg = "Error: " & msg
  return false

proc isCaptchaCorrect(c: var TForumData, antibot: string): bool =
  ## Determines whether the user typed in the captcha correctly.
  let correctRes = getValue(db,
      sql"select answer from antibot where ip = ?", c.req.ip)
  return antibot == correctRes

proc register(c: var TForumData, name, pass, antibot,
              email: string): bool =
  # Username validation:
  if name.len == 0 or not allCharsInSet(name, SecureChars):
    return setError(c, "name", "Invalid username!")
  if getValue(db, sql"select name from person where name = ?", name).len > 0:
    return setError(c, "name", "Username already exists!")

  # Password validation:
  if pass.len < 4:
    return setError(c, "new_password", "Invalid password!")

  # captcha validation:
  if not isCaptchaCorrect(c, antibot):
    return setError(c, "antibot", "Answer to captcha incorrect!")

  # email validation
  if not ('@' in email and '.' in email):
    return setError(c, "email", "Invalid email address")

  # perform registration:
  var salt = makeSalt()
  let password = makePassword(pass, salt)

  # Send activation email.
  let epoch = $int(epochTime())
  let activateUrl = c.req.makeUri("/activateEmail?nick=$1&epoch=$2&ident=$3" %
      [encodeUrl(name), encodeUrl(epoch),
       encodeUrl(makeIdentHash(name, password, epoch, salt))])

  let emailSentFut = sendEmailActivation(c.config, email, name, activateUrl)
  # Block until we send the email.
  # TODO: This is a workaround for 'var T' not being usable in async procs.
  while not emailSentFut.finished:
    poll()
  if emailSentFut.failed:
    echo("[WARNING] Couldn't send activation email: ", emailSentFut.error.msg)
    return setError(c, "email", "Couldn't send activation email")

  # add account to person table
  exec(db,
    sql("INSERT INTO person(name, password, email, salt, status, lastOnline, " &
        "ban) VALUES (?, ?, ?, ?, 'user', DATETIME('now'), ?)"), name,
              password, email, salt,
              banReasonEmailUnconfirmed)

  return true

proc resetPassword(c: var TForumData, nick, antibot: string): bool =
  # Validate captcha
  if not isCaptchaCorrect(c, antibot):
    return setError(c, "antibot", "Answer to captcha incorrect!")
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

proc checkLoggedIn(c: var TForumData) =
  let pass = c.req.cookies["sid"]
  if pass.len == 0: return
  if execAffectedRows(db,
       sql("update session set lastModified = DATETIME('now') " &
           "where ip = ? and password = ?"),
           c.req.ip, pass) > 0:
    c.userpass = pass
    c.userid = getValue(db,
      sql"select userid from session where ip = ? and password = ?",
      c.req.ip, pass)

    let row = getRow(db,
      sql"select name, email, admin from person where id = ?", c.userid)
    c.username = ||row[0]
    c.email = ||row[1]
    c.isAdmin = parseBool(||row[2])
    # Update lastOnline
    db.exec(sql"update person set lastOnline = DATETIME('now') where id = ?",
            c.userid)

  else:
    echo("SID not found in sessions. Assuming logged out.")

proc logout(c: var TForumData) =
  const query = sql"delete from session where ip = ? and password = ?"
  c.username = ""
  c.userpass = ""
  exec(db, query, c.req.ip, c.req.cookies["sid"])

proc incrementViews(c: var TForumData) =
  const query = sql"update thread set views = views + 1 where id = ?"
  exec(db, query, $c.threadId)

proc isPreview(c: TForumData): bool =
  result = c.req.params["previewBtn"].len > 0 # TODO: Could be wrong?

proc isDelete(c: TForumData): bool =
  result = c.req.params["delete"].len > 0

proc rstToHtml(content: string): string =
  result = rstgen.rstToHtml(content, {roSupportSmilies, roSupportMarkdown},
                            docConfig)

proc validateRst(c: var TForumData, content: string): bool =
  result = true
  try:
    discard rstToHtml(content)
  except EParseError:
    result = setError(c, "", getCurrentExceptionMsg())

proc crud(c: TCrud, table: string, data: varargs[string]): TSqlQuery =
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

template retrSubject(c: expr) =
  let subject {.inject.} = c.req.params["subject"]
  if subject.strip.len < 3:
    return setError(c, "subject", "Subject not long enough")

template retrContent(c: expr) =
  let content {.inject.} = c.req.params["content"]
  if content.strip.len < 10:
    return setError(c, "content", "Content not long enough")
  if not validateRst(c, content): return false

template retrPost(c: expr) =
  retrSubject(c)
  retrContent(c)

template checkLogin(c: expr) =
  if not loggedIn(c): return setError(c, "", "User is not logged in")

template checkOwnership(c, postId: expr) =
  if not c.isAdmin:
    let x = getValue(db, sql"select author from post where id = ?",
                     postId)
    if x != c.userId:
      return setError(c, "", "You are not the owner of this post")

template setPreviewData(c: expr) {.immediate, dirty.} =
  c.currentPost.subject = subject
  c.currentPost.content = content

template writeToDb(c, cr, setPostId: expr) =
  # insert a comment in the DB
  let retID = insertID(db, crud(cr, "post", "author", "ip", "header", "content", "thread"),
       c.userId, c.req.ip, subject, content, $c.threadId, "")
  discard tryExec(db, crud(cr, "post_fts", "id", "header", "content"),
       retID.int, subject, content)
  if setPostId:
    c.postId = retID.int

template sendToMailingList(c) =
  # send comment to a mailing list (if configured to do so)
  discard sendMailToMailingList(c.config, c.username, c.email, subject, content)

proc edit(c: var TForumData, postId: int): bool =
  checkLogin(c)
  if c.isPreview:
    retrPost(c)
    setPreviewData(c)
  elif c.isDelete:
    checkOwnership(c, $postId)
    if not tryExec(db, crud(crDelete, "post"), $postId):
      return setError(c, "", "database error")
    discard tryExec(db, crud(crDelete, "post_fts"), $postId)
    # delete corresponding thread:
    if execAffectedRows(db,
        sql"delete from thread where id not in (select thread from post)") > 0:
      # whole thread has been deleted, so:
      c.threadId = unselectedThread
      discard tryExec(db, sql"delete from thread_fts where id not in (select thread from post)")
    else:
      # Update corresponding thread's modified field.
      let getModifiedSql = "(select creation from post where post.thread = ?" &
          " order by creation desc limit 1)"
      let updateSql = sql("update thread set modified=" & getModifiedSql &
          " where id = ?")
      if not tryExec(db, updateSql, $c.threadId, $c.threadId):
        return setError(c, "", "database error")
    result = true
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

proc reply(c: var TForumData): bool =
  # reply to an existing thread
  checkLogin(c)
  retrPost(c)
  if c.isPreview:
    setPreviewData(c)
  else:
    writeToDb(c, crCreate, true)

    exec(db, sql"update thread set modified = DATETIME('now') where id = ?",
         $c.threadId)
    sendToMailingList(c)
    result = true

proc newThread(c: var TForumData): bool =
  # create new conversation thread (permanent or transient)
  const query = sql"insert into thread(name, views, modified) values (?, 0, DATETIME('now'))"
  checkLogin(c)
  retrPost(c)
  if c.isPreview:
    setPreviewData(c)
    c.threadID = transientThread
  else:
    c.threadID = tryInsertID(db, query, c.req.params["subject"]).int
    if c.threadID < 0: return setError(c, "subject", "Subject already exists")
    discard tryExec(db, crud(crCreate, "thread_fts", "id", "name"),
                        c.threadID, c.req.params["subject"])
    writeToDb(c, crCreate, false)
    discard tryExec(db, sql"insert into post_fts(post_fts) values('optimize')")
    discard tryExec(db, sql"insert into post_fts(thread_fts) values('optimize')")
    sendToMailingList(c)
    result = true

proc login(c: var TForumData, name, pass: string): bool =
  # get form data:
  const query =
    sql"select id, name, password, email, salt, admin, ban from person where name = ?"
  if name.len == 0:
    return c.setError("name", "Username cannot be nil.")
  var success = false
  for row in fastRows(db, query, name):
    if row[2] == makePassword(pass, row[4], row[2]):
      case row[6]
      of "": discard
      of banReasonDeactivated:
        return c.setError("name", "Your account has been deactivated.")
      else:
        return c.setError("name", "You have been banned: " & row[6])
      c.userid = row[0]
      c.username = row[1]
      c.userpass = row[2]
      c.email = row[3]
      c.isAdmin = row[5].parseBool
      success = true
      break
  if success:
    # create session:
    exec(db,
      sql"insert into session (ip, password, userid) values (?, ?, ?)",
      c.req.ip, c.userpass, c.userid)
    return true
  else:
    return c.setError("password", "Login failed!")

proc verifyIdentHash(c: var TForumData, name, epoch, ident: string): bool =
  const query =
    sql"select password, salt, strftime('%s', lastOnline) from person where name = ?"
  var row = getRow(db, query, name)
  if row[0] == "": return false
  let newIdent = makeIdentHash(name, row[0], epoch, row[1], ident)
  # Check that the user has not been logged in since this ident hash has been
  # created. Give the timestamp a certain range to prevent false negatives.
  if row[2].parseInt > (epoch.parseInt + 60): return false
  result = newIdent == ident

proc setBan(c: var TForumData, nick, reason: string): bool =
  const query =
    sql("update person set ban = ? where name = ?")
  return tryExec(db, query, reason, nick)

proc setPassword(c: var TForumData, nick, pass: string): bool =
  const query =
    sql("update person set password = ?, salt = ? where name = ?")
  var salt = makeSalt()
  result = tryExec(db, query, makePassword(pass, salt), salt, nick)

proc hasReplyBtn(c: var TForumData): bool =
  result = c.req.pathInfo != "/donewthread" and c.req.pathInfo != "/doreply"
  result = result and c.req.params["action"] != "reply"
  # If the user is not logged in and there are no page numbers then we shouldn't
  # generate the div.
  let pages = ceil(c.totalPosts / PostsPerPage).int
  result = result and (pages > 1 or c.loggedIn)
  return c.threadId >= 0 and result

proc genActionMenu(c: var TForumData): string =
  result = ""
  var btns: seq[TStyledButton] = @[]
  # TODO: Make this detection better?
  if c.req.pathInfo.normalizeUri notin noHomeBtn and not c.isThreadsList:
    btns.add(("Thread List", c.req.makeUri("/", false)))
  #echo c.loggedIn
  if c.loggedIn:
    let hasReplyBtn = c.req.pathInfo != "/donewthread" and c.req.pathInfo != "/doreply"
    if c.threadId >= 0 and hasReplyBtn:
      let replyUrl = c.genThreadUrl(action = "reply",
            pageNum = $(ceil(c.totalPosts / PostsPerPage).int)) & "#reply"
      btns.add(("Reply", replyUrl))
    btns.add(("New Thread", c.req.makeUri("/newthread", false)))
  result = c.genButtons(btns)

proc getStats(c: var TForumData, simple: bool): TForumStats =
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
    result.newestMember = ("", -1, false)
    const getUsersQuery =
      sql"select id, name, admin, strftime('%s', lastOnline), strftime('%s', creation) from person"
    for row in fastRows(db, getUsersQuery):
      let secs = if row[3] == "": 0 else: row[3].parseint
      let lastOnlineSeconds = getTime() - Time(secs)
      if lastOnlineSeconds < (60 * 5): # 5 minutes
        result.activeUsers.add((row[1], row[0].parseInt, row[2].parseBool))
      if row[4].parseInt > newestMemberCreation:
        result.newestMember = (row[1], row[0].parseInt, row[2].parseBool)
        newestMemberCreation = row[4].parseInt

proc genPagenumNav(c: var TForumData, stats: TForumStats): string =
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
    firstUrl = c.req.makeUri("/t/" & $c.threadId)
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

proc gatherTotalPostsByID(c: var TForumData, thrid: int): int =
  ## Gets the total post count of a thread.
  result = getValue(db, sql"select count(*) from post where thread = ?", $thrid).parseInt

proc gatherTotalPosts(c: var TForumData) =
  if c.totalPosts > 0: return
  # Gather some data.
  const totalPostsQuery =
      sql"select count(*) from post p, person u where u.id = p.author and p.thread = ?"
  c.totalPosts = getValue(db, totalPostsQuery, $c.threadId).parseInt

proc getPagesInThread(c: var TForumData): int =
  c.gatherTotalPosts() # Get total post count
  result = ceil(c.totalPosts / PostsPerPage).int-1

proc getPagesInThreadByID(c: var TForumData, thrid: int): int =
  result = ceil(c.gatherTotalPostsByID(thrid) / PostsPerPage).int

proc getThreadTitle(thrid: int, pageNum: int): string =
  result = getValue(db, sql"select name from thread where id = ?", $thrid)
  if pageNum notin {0,1}:
    result.add(" - Page " & $pageNum)

proc genPagenumLocalNav(c: var TForumData, thrid: int): string =
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

proc gatherUserInfo(c: var TForumData, nick: string, ui: var TUserInfo): bool =
  ui.nick = nick
  const getUIDQuery = sql"select id from person where name = ?"
  var uid = getValue(db, getUIDQuery, nick)
  if uid == "": return false
  result = true
  const totalPostsQuery =
      sql"SELECT count(*) FROM post WHERE author = ?"
  ui.posts = getValue(db, totalPostsQuery, uid).parseInt
  const totalThreadsQuery =
      sql("select count(*) from thread where id in (select thread from post where" &
         " author = ? and post.id in (select min(id) from post group by thread))")

  ui.threads = getValue(db, totalThreadsQuery, uid).parseInt
  const lastOnlineQuery =
      sql"select strftime('%s', lastOnline) from person where id = ?"
  let lastOnlineDBVal = getValue(db, lastOnlineQuery, uid)
  ui.lastOnline = if lastOnlineDBVal != "": lastOnlineDBVal.parseInt else: -1
  ui.email = getValue(db, sql"select email from person where id = ?", uid)
  ui.ban = getValue(db, sql"select ban from person where id = ?", uid)

proc genSetUserStatusUrl(c: var TForumData, nick: string, typ: string): string =
  c.req.makeUri("/setUserStatus?nick=$1&type=$2" % [nick, typ])

proc genProfile(c: var TForumData, ui: TUserInfo): string =
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
  let t2 = if ui.lastOnline != -1: getGMTime(Time(ui.lastOnline))
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
        td(case ui.ban
           of banReasonDeactivated:
             "Deactivated"
           of banReasonEmailUnconfirmed:
             "Awaiting email confirmation"
           of "":
             "Active"
           else:
             "Banned: " & ui.ban
        )
      ),
      tr(
        th(""),
        td(if c.isAdmin and ui.ban != banReasonDeactivated:
             if ui.ban == "":
               htmlgen.a(
                 href=c.genSetUserStatusUrl(ui.nick, "ban"),
                     "Ban user")
             else:
               htmlgen.a(href=c.genSetUserStatusUrl(ui.nick, "unban"),
                     "Unban user")
           else: "")
      ),
      tr(
        th(""),
        td(if c.userName == ui.nick or c.isAdmin:
             if ui.ban == "":
               htmlgen.a(href=c.genSetUserStatusUrl(ui.nick, "deactivate"),
                  "Deactivate user")
             elif ui.ban == banReasonDeactivated:
               htmlgen.a(href=c.genSetUserStatusUrl(ui.nick, "activate"),
                  "Activate user")
             elif ui.ban == banReasonEmailUnconfirmed:
               htmlgen.a(href=c.genSetUserStatusUrl(ui.nick, "activate"),
                  "Confirm user's email")
             else: ""
           else: "")
      )
    )
  ))

  result = htmlgen.`div`(id = "profile",
    htmlgen.`div`(id = "left", result))

include "forms.tmpl"
include "main.tmpl"

proc prependRe(s: string): string =
  result = if s.len == 0:
             ""
           elif s.startswith("Re:"): s
           else: "Re: " & s

template createTFD(): stmt =
  var c {.inject.}: TForumData
  init(c)
  c.req = request
  c.startTime = epochTime()
  c.isThreadsList = false
  c.pageNum = 1
  c.config = config
  if request.cookies.len > 0:
    checkLoggedIn(c)

routes:
  get "/":
    createTFD()
    c.isThreadsList = true
    var count = 0
    let threadList = genThreadsList(c, count)
    let data = genMain(c, threadList,
        additionalHeaders = genRSSHeaders(c), showRssLinks = true)
    resp data

  get "/threadActivity.xml":
    createTFD()
    c.isThreadsList = true
    resp genThreadsRSS(c), "application/atom+xml"

  get "/postActivity.xml":
    createTFD()
    resp genPostsRSS(c), "application/atom+xml"

  get "/t/@threadid/?@page?/?@postid?/?":
    createTFD()
    parseInt(@"threadid", c.threadId, -1..1000_000)

    if c.threadId == unselectedThread:
      # Thread has just been deleted.
      redirect(uri("/"))

    if @"page".len > 0:
      parseInt(@"page", c.pageNum, 0..1000_000)
    if @"postid".len > 0:
      parseInt(@"postid", c.postId, 0..1000_000)
    cond (c.pageNum > 0)
    var count = 0
    var pSubject = getThreadTitle(c.threadid, c.pageNum)
    cond validThreadId(c)
    gatherTotalPosts(c)
    if (@"action").len > 0:
      var title = ""
      case @"action"
      of "reply":
        let subject = getValue(db,
            sql"select header from post where id = (select max(id) from post where thread = ?)",
            $c.threadId).prependRe
        body = genPostsList(c, $c.threadId, count)
        cond count != 0
        body.add genFormPost(c, "doreply", "Reply", subject, "", false)
        title = "Replying to thread: " & pSubject
      of "edit":
        cond c.postId != -1
        const query = sql"select header, content from post where id = ?"
        let row = getRow(db, query, $c.postId)
        let header = ||row[0]
        let content = ||row[1]
        body = genFormPost(c, "doedit", "Edit", header, content, true)
        title = "Editing post"
      else: discard
      resp c.genMain(body, title & " - Nim Forum")
    else:
      incrementViews(c)
      let posts = genPostsList(c, $c.threadId, count)
      cond count != 0
      resp genMain(c, posts, pSubject & " - Nim Forum")

  get "/page/?@page?/?":
    createTFD()
    c.isThreadsList = true
    cond (@"page" != "")
    parseInt(@"page", c.pageNum, 0..1000_000)
    cond (c.pageNum > 0)
    var count = 0
    let list = genThreadsList(c, count)
    if count == 0:
      pass()
    resp genMain(c, list, "Page " & $c.pageNum & " - Nim Forum",
                 genRSSHeaders(c), showRssLinks = true)

  get "/profile/@nick/?":
    createTFD()
    cond (@"nick" != "")
    var userinfo: TUserInfo
    if gatherUserInfo(c, @"nick", userinfo):
      resp genMain(c, c.genProfile(userinfo),
                   @"nick" & "'s profile - Nim Forum")
    else:
      halt()

  get "/login/?":
    createTFD()
    resp genMain(c, genFormLogin(c), "Log in - Nim Forum")

  get "/logout/?":
    createTFD()
    logout(c)
    redirect(uri("/"))

  get "/register/?":
    createTFD()
    resp genMain(c, genFormRegister(c), "Register - Nim Forum")

  template readIDs(): stmt =
    # Retrieve the threadid, postid and pagenum
    if (@"threadid").len > 0:
      parseInt(@"threadid", c.threadId, -1..1000_000)
    if (@"postid").len > 0:
      parseInt(@"postid", c.postId, -1..1000_000)

  template finishLogin(): stmt =
    setCookie("sid", c.userpass, daysForward(7))
    redirect(uri("/"))

  template handleError(action: string, topText: string, isEdit: bool): stmt =
    if c.isPreview:
      body.add genPostPreview(c, @"subject", @"content",
                              c.userName, $getGMTime(getTime()))
    body.add genFormPost(c, action, topText, reuseText, reuseText, isEdit)
    resp genMain(c, body(), "Nim Forum - " &
                            (if c.isPreview: "Preview" else: "Error"))

  post "/dologin":
    createTFD()
    if login(c, @"name", @"password"):
      finishLogin()
    else:
      c.isThreadsList = true
      var count = 0
      let threadList = genThreadsList(c, count)
      let data = genMain(c, threadList,
          additionalHeaders = genRSSHeaders(c), showRssLinks = true)
      resp data

  post "/doregister":
    createTFD()
    if c.register(@"name", @"new_password", @"antibot", @"email"):
      resp genMain(c, "You are now registered. You must now confirm your" &
          " email address by clicking the link sent to " & @"email",
          "Registration successful - Nim Forum")
    else:
      resp c.genMain(genFormRegister(c))

  post "/donewthread":
    createTFD()
    if newThread(c):
      redirect(uri("/"))
    else:
      body = ""
      handleError("donewthread", "New thread", false)

  post "/doreply":
    createTFD()
    readIDs()
    if reply(c):
      redirect(c.genThreadUrl(pageNum = $(c.getPagesInThread+1)) & "#" & $c.postId)
    else:
      var count = 0
      if c.isPreview:
        c.pageNum = c.getPagesInThread+1
      body = genPostsList(c, $c.threadId, count)
      handleError("doreply", "Reply", false)

  post "/doedit":
    createTFD()
    readIDs()
    if edit(c, c.postId):
      redirect(c.genThreadUrl(postId = $c.postId,
                              pageNum = $(c.getPagesInThread+1)))
    else:
      body = ""
      handleError("doedit", "Edit", true)

  get "/newthread/?":
    createTFD()
    resp genMain(c, genFormPost(c, "donewthread", "New thread", "", "", false),
                 "New Thread - Nim Forum")

  get "/setUserStatus/?":
    createTFD()
    cond (@"nick" != "")
    cond (@"type" != "")
    var formBody = "<input type=\"hidden\" name=\"nick\" value=\"" &
                      @"nick" & "\">"
    var del = false
    var content = ""
    echo("Got type: ", @"type")
    case @"type"
    of "ban":
      formBody.add "<input type='text' name='reason' />" &
          "<input type='submit' name='banBtn' value='Ban' />"
      content =
        htmlgen.p("Please enter a reason for banning this user:")
    of "unban":
      formBody.add "<input type='submit' name='unbanBtn' value='Unban' />"
      content =
        htmlgen.p("Are you sure you wish to unban ", htmlgen.b(@"nick"),
          "?")
      del = true
    of "deactivate":
      formBody.add "<input type='hidden' name='reason' value='" &
          banReasonDeactivated & "' />" &
          "<input type='submit' name='actBtn' value='Deactivate' />"
      content =
        htmlgen.p("Are you sure you wish to deactivate ", htmlgen.b(@"nick"),
          "?")
    of "activate":
      formBody.add "<input type='submit' name='actBtn' value='Activate' />"
      content =
        htmlgen.p("Are you sure you wish to activate ", htmlgen.b(@"nick"),
          "?")
      del = true
    formBody.add "<input type='hidden' name='del' value='" & $del & "'/>"
    content = htmlgen.form(action = c.req.makeUri("/dosetban"),
        `method` = "POST", formBody) & content
    resp genMain(c, content, "Set user status - Nim Forum")

  post "/dosetban":
    createTFD()
    cond (@"nick" != "")
    if not c.isAdmin and @"nick" != c.userName:
      resp genMain(c, "You cannot ban this user.", "Error - Nim Forum")
    if @"reason" == "" and @"del" != "true":
      resp genMain(c, "Invalid ban reason.", "Error - Nim Forum")
    let result =
      if @"del" == "true":
        # Remove the ban.
        setBan(c, @"nick", "")
      else:
        setBan(c, @"nick", @"reason")
    if result:
      redirect(c.req.makeUri("/profile/" & @"nick"))
    else:
      resp genMain(c, "Failed to change the ban status of user.",
          "Error - Nim Forum")

  get "/setpassword/?":
    createTFD()
    cond (@"nick" != "")
    cond (@"pass" != "")
    if not c.isAdmin:
      resp genMain(c, "You cannot change this user's pass.", "Error - Nim Forum")
    let res = setPassword(c, @"nick", @"pass")
    if res:
      resp genMain(c, "Success", "Nim Forum")
    else:
      resp genMain(c, "Failure", "Nim Forum")

  get "/activateEmail/?":
    createTFD()
    cond (@"nick" != "")
    cond (@"epoch" != "")
    cond (@"ident" != "")
    var epoch: BiggestInt = 0
    cond(parseBiggestInt(@"epoch", epoch) > 0)
    var success = false
    if verifyIdentHash(c, @"nick", $epoch, @"ident"):
      let ban = db.getValue(sql"select ban from person where name = ?", @"nick")
      if ban == banReasonEmailUnconfirmed:
        success = setBan(c, @"nick", "")

    if success:
      resp genMain(c, "Account activated", "Nim Forum")
    else:
      resp genMain(c, "Account activation failed", "Nim Forum")

  get "/emailResetPassword/?":
    createTFD()
    cond (@"nick" != "")
    cond (@"epoch" != "")
    cond (@"ident" != "")
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
    cond (@"nick" != "")
    cond (@"epoch" != "")
    cond (@"ident" != "")
    cond (@"password" != "")
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
    cond (@"nick" != "")

    if resetPassword(c, @"nick", @"antibot"):
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
    c.search = q.replace("\"","&quot;");
    if @"page".len > 0:
      parseInt(@"page", c.pageNum, 0..1000_000)
      cond (c.pageNum > 0)
    iterator searchResults(): db_sqlite.TRow {.closure, tags: [FReadDB].} =
      const queryFT = "fts.sql".slurp.sql
      for rowFT in fastRows(db, queryFT,
                    [q,q,$ThreadsPerPage,$c.pageNum,$ThreadsPerPage,q,
                     q,q,$ThreadsPerPage,$c.pageNum,$ThreadsPerPage,q]):
        yield rowFT
    resp genMain(c, genSearchResults(c, searchResults, count),
                 additionalHeaders = genRSSHeaders(c), showRssLinks = true)

  # tries first to read html, then to read rst, convert ot html, cache and return
  template textPage(path: string): stmt =
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

when isMainModule:
  docConfig = rstgen.defaultConfig()
  docConfig["doc.smiley_format"] = "/images/smilieys/$1.png"
  math.randomize()
  db = open(connection="nimforum.db", user="postgres", password="",
              database="nimforum")
  isFTSAvailable = db.getAllRows(sql("SELECT name FROM sqlite_master WHERE " &
      "type='table' AND name='post_fts'")).len == 1
  config = loadConfig()
  var http = true
  if paramCount() > 0:
    if paramStr(1) == "scgi":
      http = false

  #run("", port = TPort(9000), http = http)

  runForever()
  db.close()

