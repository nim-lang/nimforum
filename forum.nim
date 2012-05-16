#
#
#              The Nimrod Forum
#        (c) Copyright 2012 Andreas Rumpf
#
#    All rights reserved.
#

import
  os, strutils, times, md5, strtabs, cgi, math, db_sqlite, matchers,
  rst, rstgen, captchas, sockets, scgi, jester

const
  unselectedThread = -1
  transientThread = 0
  websiteLoc = ""

type
  TCrud = enum crCreate, crRead, crUpdate, crDelete

  TSession = object of TObject
    threadid: int
    postid: int
    userName, userPass, email: string
    isAdmin: bool

  TPost = tuple[subject, content: string]

  TForumData = object of TSession
    req: TRequest
    userid: string
    actionContent: string
    errorMsg, loginErrorMsg: string
    invalidField: string
    currentPost: TPost
    startTime: float

  TStyledButton = tuple[text: string, link: string]

  TForumStats = object
    totalUsers: int
    totalPosts: int
    totalThreads: int
    newestMember: tuple[nick: string, id: int, isAdmin: bool]
    activeUsers: seq[tuple[nick: string, id: int, isAdmin: bool]]

var
  db: TDbConn
  docConfig: PStringTable
  
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
          else: XMLencode(c.req.params[name])
  return """<input type="text" name="$1" maxlength="$2" value="$3" $4/>""" % [
    name, $maxlength, x, if size != -1: "size=\"" & $size & "\"" else: ""]

proc TextAreaWidget(c: TForumData, name, defaultText: string,  
                    width = 80, height = 20): string =
  let x = if defaultText != reuseText: defaultText
          else: XMLencode(c.req.params[name])
  return """<textarea name="$1" cols="$2" rows="$3">$4</textarea>""" % [
    name, $width, $height, x]

proc FieldValid(c: TForumData, name, text: string): string = 
  if name == c.invalidField: 
    result = """<span style="color:red">$1</span>""" % text
  else:
    result = text

proc genThreadUrl(c: TForumData, postId = "", action = "", threadid = ""): string =
  result = "/t/" & (if threadid == "": $c.threadId else: threadid)
  if action != "":
    result.add("?action=" & action)
    if postId != "":
      result.add("&postid=" & postid)
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

proc formatTimestamp(t: int): string =
  let t2 = getGMTime(TTime(t))
  return t2.format("ddd',' d MMM yyyy HH':'mm 'UTC'")

proc genGravatar(email: string, size: int = 80): string =
  let emailMD5 = email.toLower.toMD5
  result = "<img src=\"$1\" />" % 
    ("http://www.gravatar.com/avatar/" & $emailMD5 & "?s=" & $size &
     "&d=identicon")

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
  try:
    result = devRandomSalt()
  except EIO:
    result = randomSalt()

proc makePassword(password, salt: string): string =
  ## Creates an MD5 hash by combining password and salt.
  result = getMD5(salt & getMD5(password))

# -----------------------------------------------------------------------------
template `||`(x: expr): expr = (if not isNil(x): x else: "")

proc validThreadId(c: TForumData): bool =
  result = GetValue(db, sql"select id from thread where id = ?", 
                    $c.threadId).len > 0
  
proc antibot(c: var TForumData): string = 
  let a = math.random(10)+1
  let b = math.random(1000)+1
  let answer = $(a+b)
  
  Exec(db, sql"delete from antibot where ip = ?", c.req.ip)
  let CaptchaId = TryInsertID(db, 
    sql"insert into antibot(ip, answer) values (?, ?)", c.req.ip, 
    answer).int mod 10_000
  let CaptchaFile = getCaptchaFilename(CaptchaId)
  createCaptcha(CaptchaFile, $a & "+" & $b)
  result = """<img src="$1" />""" % getCaptchaUrl(captchaId)

const
  SecureChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '\128'..'\255'}

proc setError(c: var TForumData, field, msg: string): bool {.inline.} =
  c.invalidField = field
  c.errorMsg = "Error: " & msg
  return false

proc register(c: var TForumData, name, pass, antibot, email: string): bool = 
  # Username validation:
  if name.len == 0 or not allCharsInSet(name, SecureChars):
    return setError(c, "name", "Invalid username!")
  if GetValue(db, sql"select name from person where name = ?", name).len > 0:
    return setError(c, "name", "Username already exists!")
  
  # Password validation:
  if pass.len < 4:
    return setError(c, "new_password", "Invalid password!")

  # antibot validation:
  let correctRes = GetValue(db, 
    sql"select answer from antibot where ip = ?", c.req.ip)
  if antibot != correctRes:
    return setError(c, "antibot", "You seem to be a bot!")
    
  # email validation
  if not validEmailAddress(email):
    return setError(c, "email", "Invalid email address")
  
  # perform registration:
  var salt = makeSalt()
  Exec(db, sql("INSERT INTO person(name, password, email, salt, status, lastOnline) " &
              "VALUES (?, ?, ?, ?, 'user', DATETIME('now'))"), name, 
              makePassword(pass, salt), email, salt)
  #  return setError(c, "", "Could not create your account!")
  return true

proc checkLoggedIn(c: var TForumData) = 
  let pass = c.req.cookies["sid"]
  if pass.len == 0: return
  if ExecAffectedRows(db, 
       sql("update session set lastModified = DATETIME('now') " &
           "where ip = ? and password = ?"), 
           c.req.ip, pass) > 0:
    c.userpass = pass
    c.userid = GetValue(db, 
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
  Exec(db, query, c.req.ip, c.req.cookies["sid"])

proc incrementViews(c: var TForumData) = 
  const query = sql"update thread set views = views + 1 where id = ?"
  Exec(db, query, $c.threadId)

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

proc crud(c: TCrud, table: string, data: openArray[string]): TSqlQuery =
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
  let subject = c.req.params["subject"]
  if subject.len < 3: return setError(c, "subject", "Subject not long enough")
  
template retrContent(c: expr) =
  let content = c.req.params["content"]
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

template setPreviewData(c: expr) =
  c.currentPost.subject = subject
  c.currentPost.content = content

template writeToDb(c, cr, postId: expr) =
  exec(db, crud(cr, "post", "author", "ip", "header", "content", "thread"),
       c.userId, c.req.ip, subject, content, $c.threadId, postId)

proc edit(c: var TForumData, postId: int): bool =
  checkLogin(c)  
  if c.isPreview:
    retrPost(c)
    setPreviewData(c)
  elif c.isDelete:
    checkOwnership(c, $postId)
    if not TryExec(db, crud(crDelete, "post"), $postId):
      return setError(c, "", "database error")
    # delete corresponding thread:
    if ExecAffectedRows(db,
        sql"delete from thread where id not in (select thread from post)") > 0:
      # whole thread has been deleted, so:
      c.threadId = unselectedThread
    result = true
  else:
    checkOwnership(c, $postId)
    retrPost(c)
    exec(db, crud(crUpdate, "post", "header", "content"),
         subject, content, $postId)
    result = true
  
proc reply(c: var TForumData): bool = 
  checkLogin(c)
  retrPost(c)
  if c.isPreview:
    setPreviewData(c)
  else:
    writeToDb(c, crCreate, "")
    exec(db, sql"update thread set modified = DATETIME('now') where id = ?",
         $c.threadId)
    result = true
  
proc newThread(c: var TForumData): bool =
  const query = sql"insert into thread(name, views, modified) values (?, 0, DATETIME('now'))"
  checkLogin(c)
  retrPost(c)
  if c.isPreview:
    setPreviewData(c)
    c.threadID = transientThread
  else:
    c.threadID = TryInsertID(db, query, c.req.params["subject"]).int
    if c.threadID < 0: return setError(c, "subject", "Subject already exists")
    writeToDb(c, crCreate, "")
    result = true

proc login(c: var TForumData, name, pass: string): bool = 
  # get form data:
  const query = 
    sql"select id, name, password, email, salt, admin from person where name = ?"
  if name.len == 0:
    return c.setError("name", "Username cannot be nil.")
  var success = false
  for row in FastRows(db, query, name):
    if row[2] == makePassword(pass, row[4]):
      c.userid = row[0]
      c.username = row[1]
      c.userpass = row[2]
      c.email = row[3]
      c.isAdmin = row[5].parseBool
      success = true
      break
  if success:
    # create session:
    Exec(db, 
      sql"insert into session (ip, password, userid) values (?, ?, ?)", 
      c.req.ip, c.userpass, c.userid)
    return true
  else:
    return c.setError("password", "Login failed!")

proc genActionMenu(c: var TForumData): string =
  result = ""
  var btns: seq[TStyledButton] = @[]
  if c.req.pathInfo != "/":
    btns.add(("Thread List", c.req.makeUri("/", false)))
  if c.loggedIn:
    let hasReplyBtn = c.req.pathInfo != "/donewthread" and c.req.pathInfo != "/doreply"
    if c.threadId >= 0 and hasReplyBtn:
      let replyUrl = c.genThreadUrl("", "reply") & "#reply"
      btns.add(("Reply", replyUrl))
    btns.add(("New Thread", c.req.makeUri("/newthread", false)))
  result = c.genButtons(btns)

proc getStats(c: var TForumData): TForumStats =
  const totalUsersQuery = 
    sql"select count(*) from person"
  result.totalUsers = getValue(db, totalUsersQuery).parseInt
  const totalPostsQuery =
    sql"select count(*) from post"
  result.totalPosts = getValue(db, totalPostsQuery).parseInt
  const totalThreadsQuery =
    sql"select count(*) from thread"
  result.totalThreads = getValue(db, totalThreadsQuery).parseInt
  
  var newestMemberCreation = 0
  result.activeUsers = @[]
  const getUsersQuery =
    sql"select id, name, admin, strftime('%s', lastOnline), strftime('%s', creation) from person"
  for row in fastRows(db, getUsersQuery):
    let secs = if row[3] == "": 0 else: row[3].parseint
    let lastOnlineSeconds = getTime() - TTime(secs)
    if lastOnlineSeconds < (60 * 5): # 5 minutes
      result.activeUsers.add((row[1], row[0].parseInt, row[2].parseBool))
    if row[4].parseInt > newestMemberCreation:
      result.newestMember = (row[1], row[0].parseInt, row[2].parseBool)
      newestMemberCreation = row[4].parseInt

include "forms.tmpl"
include "main.tmpl"

proc prependRe(s: string): string =
  result = if s.len == 0:
             "" 
           elif s.startswith("Re:"): s
           else: "Re: " & s

template createTFD(): stmt =
  var c: TForumData
  init(c)
  c.req = request
  c.startTime = epochTime()
  if request.cookies.len > 0:
    checkLoggedIn(c)

get "/":
  createTFD()
  resp genMain(c, genThreadsList(c), true)

get "/t/@threadid/?":
  createTFD()
  parseInt(@"threadid", c.threadId, -1..1000_000)
  if (@"postid").len > 0:
    parseInt(@"postid", c.postId, -1..1000_000)
  
  if (@"action").len > 0:
    case @"action"
    of "reply":
      let subject = GetValue(db,
          sql"select header from post where id = (select max(id) from post where thread = ?)", 
          $c.threadId).prependRe
      body = genPostsList(c, $c.threadId)
      echo(c.threadId)
      body.add genFormPost(c, "doreply", "Reply", subject, "", false)
    of "edit":
      cond c.postId != -1
      const query = sql"select header, content from post where id = ?"
      let row = getRow(db, query, $c.postId)
      let header = ||row[0]
      let content = ||row[1]
      body = genFormPost(c, "doedit", "Edit", header, content, true)
    resp c.genMain(body)
  else:
    cond validThreadId(c)
    incrementViews(c)
    resp genMain(c, genPostsList(c, $c.threadId))

get "/login/?":
  createTFD()
  resp genMain(c, genFormLogin(c))

get "/logout/?":
  createTFD()
  logout(c)
  redirect(uri("/"))

get "/register/?":
  createTFD()
  resp genMain(c, genFormRegister(c))

template readIDs(): stmt =
  # Retrieve the threadid and postid
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
  resp genMain(c, body)

post "/dologin":
  createTFD()
  if login(c, @"name", @"password"):
    finishLogin()
  else:
    resp c.genMain(genFormLogin(c))

post "/doregister":
  createTFD()
  if c.register(@"name", @"new_password", @"antibot", @"email"):
    discard c.login(@"name", @"new_password")
    finishLogin()
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
    redirect(c.genThreadUrl())
  else:
    body = genPostsList(c, $c.threadId)
    handleError("doreply", "Reply", false)

post "/doedit":
  createTFD()
  readIDs()
  if edit(c, c.postId):
    redirect(c.genThreadUrl())
  else:
    body = ""
    handleError("doedit", "Edit", true)

get "/newthread/?":
  createTFD()
  resp genMain(c, genFormPost(c, "donewthread", "New thread", "", "", false))

when isMainModule:
  docConfig = rstgen.defaultConfig()
  math.randomize()
  db = Open(connection="nimforum.db", user="postgres", password="", 
              database="nimforum")
  var http = true
  if paramCount() > 0:
    if paramStr(1) == "scgi":
      http = false
  run(websiteLoc, port = TPort(9000), http = http)
  db.close()

