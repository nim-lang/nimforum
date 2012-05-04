#
#
#              The Nimrod Forum
#        (c) Copyright 2012 Andreas Rumpf
#
#    All rights reserved.
#

import
  os, strutils, times, md5, strtabs, cgi, math, db_sqlite, matchers,
  rst, docgen, msgs, captchas, sockets, scgi, cookies

const
  unselectedThread = -1
  transientThread = 0
  websiteLoc = "/"
  postAction = "/"

type
  TCrud = enum crCreate, crRead, crUpdate, crDelete
  TForumAction = enum
    actionShow = "show",
    actionLoginForm = "login",
    actionLogin = "dologin",
    actionLogout = "logout",
    actionRegisterForm = "register",
    actionRegister = "doregister",
    actionNewThreadForm = "newthread",
    actionNewThread = "donewthread",
    actionReplyForm = "reply",
    actionReply = "doreply",
    actionEditForm = "edit",
    actionEdit = "doedit",
    action404

  TSession = object of TObject
    threadid: int
    postid: int
    userName, userPass, email: string
    isAdmin: bool

  TPost = tuple[subject, content: string]

  TForumData = object of TSession
    action: TForumAction
    cgiData: PStringTable
    ip: string
    userid: string
    actionContent: string
    errorMsg, loginErrorMsg: string
    invalidField: string
    currentPost: TPost
    reqUrl: string
    startTime: float
    cookieData: PStringTable

  TStyledButton = tuple[text: string, action: TForumAction, tid: string]

  TRequest* {.final.} = object  ## a request for the application to process
    ip*: string                 ## IP of request
    url*: string                ## requested URL
    vars*: PStringTable         ## other variables
    startTime*: float

var
  db: TDbConn
  
proc init(c: var TForumData) = 
  c.userPass = ""
  c.userName = ""
  c.threadId = unselectedThread
  c.postId = -1
  
  c.action = actionShow
  c.ip = ""
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
          else: XMLencode(c.cgiData[name])
  return """<input type="text" name="$1" maxlength="$2" value="$3" $4/>""" % [
    name, $maxlength, x, if size != -1: "size=\"" & $size & "\"" else: ""]

proc TextAreaWidget(c: TForumData, name, defaultText: string,  
                    width = 80, height = 20): string =
  let x = if defaultText != reuseText: defaultText
          else: XMLencode(c.cgiData[name])
  return """<textarea name="$1" cols="$2" rows="$3">$4</textarea>""" % [
    name, $width, $height, x]

proc FieldValid(c: TForumData, name, text: string): string = 
  if name == c.invalidField: 
    result = """<span style="color:red">$1</span>""" % text
  else:
    result = text

proc genQuery(c: var TForumData, action: TForumAction, target: string): string =
  result = websiteLoc
  case action
  of actionShow:
    if target != "":
      result.add("t/" & target)
  of actionReplyForm:
    result.add("t/" & target & "?action=reply")
  of actionEditForm:
    result.add("t/" & $c.threadid & "?action=edit&postid=" & target)
  else:
    result.add($action & "/" & target)

proc FormSession(c: var TForumData, nextAction: TForumAction): string =
  return """<input type="hidden" name="action" value="$1" />
            <input type="hidden" name="threadid" value="$2" />
            <input type="hidden" name="postid" value="$3" />""" % [
    $nextAction, $c.threadId, $c.postid]

proc UrlButton(c: var TForumData, text: string, 
               nextAction: TForumAction, target=""): string =
  return ("""<a class="url_button" href="$1">$2</a>""") % [
    c.genQuery(nextAction, target), text]

proc genButtons(c: var TForumData, btns: seq[TStyledButton]): string =
  result = ""
  if btns.len == 1:
    var anchor = ""
    if btns[0].action == actionReplyForm:
      anchor = "#reply"
    
    result = ("""<a class="active button" href="$1$3">$2</a>""") % [
      c.genQuery(btns[0].action, btns[0].tid), btns[0].text, anchor]
  else:
    for i, btn in pairs(btns):
      var anchor = ""
      if btns[i].action == actionReplyForm:
        anchor = "#reply"
    
      var class = ""
      if i == 0: class = "left "
      elif i == btns.len()-1: class = "right "
      else: class = "middle "
      result.add(("""<a class="$3active button" href="$1$4">$2</a>""") % [
        c.genQuery(btns[i].action, btns[i].tid), btns[i].text, class, anchor])

proc genSlash(c: var TForumData): string =
  let reqPath = c.reqUrl
  if reqPath.endswith("/"):
    return ""
  else: return reqPath & "/"

proc formatTimestamp(t: int): string =
  let t2 = getGMTime(TTime(t))
  result = ""
  result.add(`$`(t2.weekday)[ .. 2] & ", ")
  result.add($t2.monthday & " ")
  result.add(`$`(t2.month)[ .. 2] & " ")
  result.add($t2.year & " ")
  if t2.hour < 10:
    result.add("0")
  result.add($t2.hour & ":")
  if t2.minute < 10:
    result.add("0")
  result.add($t2.minute)

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
  
  Exec(db, sql"delete from antibot where ip = ?", c.ip)
  let captureId = TryInsertID(db, 
    sql"insert into antibot(ip, answer) values (?, ?)", c.ip, 
    answer).int mod 10_000
  let captureFile = "captchas/captcha_" & $captureId & ".png"
  createCapture(captureFile, $a & "+" & $b)
  result = """<img src="$1" />""" % captureFile

const
  SecureChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '\128'..'\255'}

proc setError(c: var TForumData, field, msg: string): bool {.inline.} =
  c.invalidField = field
  c.errorMsg = "Error: " & msg
  return false

proc register(c: var TForumData): bool = 
  # get form data:
  let name = c.cgiData["name"]
  let pass = c.cgiData["new_password"]
  let antibot = c.cgiData["antibot"]
  let email = c.cgiData["email"]
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
    sql"select answer from antibot where ip = ?", c.ip)
  if antibot != correctRes:
    return setError(c, "antibot", "You seem to be a bot!")
    
  # email validation
  if not validEmailAddress(email):
    return setError(c, "email", "Invalid email address")
  
  # perform registration:
  var salt = makeSalt()
  Exec(db, sql("INSERT INTO person(name, password, email, salt, status) " &
              "VALUES (?, ?, ?, ?, 'user')"), name, 
              makePassword(pass, salt), email, salt)
  #  return setError(c, "", "Could not create your account!")
  return true

proc checkLoggedIn(c: var TForumData) = 
  let pass = c.cookieData["sid"]
  if pass.len == 0: return
  if ExecAffectedRows(db, 
       sql("update session set lastModified = DATETIME('now') " &
           "where ip = ? and password = ?"), 
           c.ip, pass) > 0:
    c.userpass = pass
    c.userid = GetValue(db, 
      sql"select userid from session where ip = ? and password = ?", 
      c.ip, pass)
      
    let row = getRow(db,
      sql"select name, email, admin from person where id = ?", c.userid)
    c.username = ||row[0]
    c.email = ||row[1]
    c.isAdmin = parseBool(||row[2])
  else:
    echo("not found login")

proc logout(c: var TForumData) =
  const query = sql"delete from session where ip = ? and password = ?"
  c.username = ""
  c.userpass = ""
  Exec(db, query, c.ip, c.cookieData["sid"])

proc incrementViews(c: var TForumData) = 
  const query = sql"update thread set views = views + 1 where id = ?"
  Exec(db, query, $c.threadId)

proc isPreview(c: TForumData): bool =
  result = c.cgiData["previewBtn"].len > 0

proc isDelete(c: TForumData): bool =
  result = c.cgiData["delete"].len > 0

proc validateRst(c: var TForumData, content: string): bool =
  result = true
  try:
    discard content.rstToHtml({roSupportSmilies})
  except ERecoverableError:
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
  let subject = c.cgiData["subject"]
  if subject.len < 3: return setError(c, "subject", "Subject not long enough")
  
template retrContent(c: expr) =
  let content = c.cgiData["content"]
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
       c.userId, c.ip, subject, content, $c.threadId, postId)

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
    c.threadID = TryInsertID(db, query, c.cgiData["subject"]).int
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
      c.ip, c.userpass, c.userid)
    return true
  else:
    return c.setError("password", "Login failed!")

proc genActionMenu(c: var TForumData): string =
  result = ""
  var btns: seq[TStyledButton] = @[]
  if c.threadId >= 0:
    btns.add(("Thread List", actionShow, ""))
  if c.loggedIn: 
    if c.threadId >= 0:
      btns.add(("Reply", actionReplyForm, $c.threadId))
    btns.add(("New Thread", actionNewThreadForm, ""))
  result = c.genButtons(btns)

include "forms.tmpl"
include "main.tmpl"

proc contentAtPosition(c: var TForumData): string = 
  if c.threadId == transientThread:
    result = c.genPostPreview(c.currentPost.subject, 
                              c.currentPost.content, 
                              c.username, $getGMTime(getTime()))
  elif validThreadId(c):
    result = genPostsList(c, $c.threadId)
  else:
    result = genThreadsList(c)

proc prependRe(s: string): string =
  result = if s.len == 0:
             "" 
           elif s.startswith("Re:"): s
           else: "Re: " & s

proc dispatch(c: var TForumData): tuple[status, content: string,
                                        headers: PStringTable] =
  template `@`(x: expr): expr = c.cgiData[x]
  
  template redirect(): stmt =
    result[0] = "303 See Other"
    let q =  c.genQuery(actionShow, $c.threadId)
    result[2] = {"Location": q}.newStringTable()
  
  template successfulLogin() =
    redirect()
    # TODO: Security risk: I'm not sure that using the hashed password as the 
    # sid is the best idea...
    var tim = TTime(int(getTime()) + 7 * (60 * 60 * 24)) # 7 days added
    result[2]["Set-Cookie"] = setCookie("sid", c.userpass, 
                                        tim.getGMTime(), noName = true)
  
  let tid = @"threadid"
  if tid.len > 0:
    parseInt(tid, c.threadId, -1..1000_000)
  let pid = @"postid"
  if pid.len > 0:
    parseInt(pid, c.postId, -1..1000_000)
  
  result[0] = "200 OK"
  result[1] = ""
  result[2] = {"Content-Type": "text/html"}.newStringTable
  case c.action
  of actionShow:
    if tid.len > 0:
      incrementViews(c)
    result[1] = contentAtPosition(c)
  of actionRegisterForm:
    result[1] = genFormRegister(c)
  of actionRegister:
    if register(c):
      discard login(c, @"name", @"new_password")
      successfulLogin()
    else:
      result[1] = genFormRegister(c)
  of actionLoginForm:
    result[1] = genFormLogin(c)
  of actionLogin:
    if login(c, @"name", @"password"):
      successfulLogin()
    else:
      result[1] = genFormLogin(c)
  of actionLogout:
    logout(c)
    redirect()
  of actionReplyForm:
    let subject = GetValue(db,
      sql"select header from post where id = (select max(id) from post where thread = ?)", 
      $c.threadId).prependRe
    result[1] = contentAtPosition(c)
    result[1].add genFormPost(c, actionReply, false, subject, "")
  of actionReply:
    if reply(c):
      redirect()
    else:
      result[1] = contentAtPosition(c)
      if c.isPreview:
        result[1] = genPostPreview(c, @"subject", @"content", 
                                c.userName, $getGMTime(getTime()))
      result[1].add genFormPost(c, actionReply, false, reuseText, reuseText)
  of actionEditForm:
    const query = sql"select header, content from post where id = ?"
    let row = getRow(db, query, $c.postId)
    let header = ||row[0]
    let content = ||row[1]
    result[1] = genFormPost(c, actionEdit, true, header, content)
  of actionEdit:
    if edit(c, c.postId):
      redirect()
    else:
      if c.isPreview:
        result[1] = genPostPreview(c, @"subject", @"content", 
                                   c.userName, $getGMTime(getTime()))
      result[1].add genFormPost(c, actionEdit, true, reuseText, reuseText)
  of actionNewThreadForm:
    result[1] = genFormPost(c, actionNewThread, false, "", "")
  of actionNewThread:
    if newThread(c):
      redirect()
    else:
      if c.isPreview:
        result[1] = genPostPreview(c, @"subject", @"content", 
                                c.userName, $getGMTime(getTime()))
      result[1].add genFormPost(c, actionNewThread, false, reuseText, reuseText)
  of action404:
    result[0] = "404 Not Found"
    result[1] = ""
    result[2] = newStringTable()
  
  if result[0] == "200 OK":
    result[1] = genMain(c, result[1])

proc normalizeDocURI(url: string): string =
  ## Adds a leading / if one doesn't exist.
  result = if url[url.len-1] != '/': url & '/' else: url

proc getAction(cgiData: PStringTable): TForumAction =
  var a = cgiData["action"]
  
  var path = ""
  let url = cgiData["DOCUMENT_URI"].normalizeDocURI
  if url.startswith(websiteLoc):
    path = url.substr(websiteLoc.len)
    if path.len != 0:
      if path[path.len-1] == '/': path = path.substr(0, path.len()-2)
    echo "PATH: ", path
  else: return action404
  
  if path == "":
    if a != "":
      result = parseEnum[TForumAction](a, action404)
    else:
      result = actionShow
  else:
    var slashes = path.split('/')
    case slashes[0]
    of "t", "thread":
      if slashes.len() > 1:
        cgiData["threadid"] = slashes[1]
        case a
        of "reply": result = actionReplyForm
        of "edit": result = actionEditForm
        else: result = actionShow
      else:
        result = action404
    else:
      result = parseEnum[TForumAction](path, action404)
      echo("Parsed ", path, " as ", result) 

proc processRequest(r: TRequest): tuple[status, content: string,
                                        headers: PStringTable] =
  try:
    var c: TForumData
    init(c)
    c.ip = r.ip
    c.reqUrl = r.url
    c.startTime = r.startTime
    
    assert c.ip.len > 0
    c.cgiData = r.vars
    c.cookieData = parseCookies(c.cgiData["HTTP_COOKIE"])
    echo(c.cookieData)
    if c.cookieData.len > 0:
      checkLoggedIn(c)
    if c.cgiData.len > 0:
      c.action = getAction(c.cgiData)

    echo c.cgiData
    echo(c.action)
    result = dispatch(c)
  except:
    result[0] = "500 Internal Server Error"
    result[1] = "Internal Error: " & getCurrentExceptionMsg()
    result[2] = newStringTable()

proc extractDirFile(s: string): tuple[dir, file: string] = 
  var last = s.len-1
  while last > 0 and s[last] == '/': dec last
  var splitPoint = last-1
  while splitPoint >= 0 and s[splitPoint] != '/': dec splitPoint
  
  result.file = s.substr(splitPoint+1, last)
  # skip '/'
  var splitPoint2 = splitPoint-1
  while splitPoint2 >= 0 and s[splitPoint2] != '/': dec splitPoint2
  result.dir = s.substr(splitPoint2+1, splitPoint-1)

proc processFile(r: TRequest): tuple[isFile: bool, 
                                     contentType, content: string] =  
  try:
    let url = r.vars["DOCUMENT_URI"].normalizeDocURI
    let (dir, file) = extractDirFile(url)
    case dir
    of "css":
      result = (true, "text/css", readFile("style/" & file))
    of "captchas":
      result = (true, "image/png", readFile("captchas/" & file))
    of "smilies":
      result = (true, "image/gif", readFile("images/smilies/" & file))
    else:
      result = (false, "", "")
  except:
    result = (false, "", "")

# ------------------ main file ----------------------------------------------

var s: TScgiState

proc shutdown() {.noconv.} =
  s.close()
  writeStackTrace()
  quit 1
  
system.setControlCHook(shutdown)

when not defined(writeStatusContent):
  proc writeStatusContent(c: TSocket, status, content: string, 
                          headers: PStringTable) =
    var strHeaders = ""
    for key, value in headers:
      strHeaders.add(key & ": " & value & "\r\L")
    c.send("Status: " & status & "\r\L" & strHeaders & "\r\L")
    c.send(content)

proc main() =
  docgen.setupConfig()
  math.randomize()
  db = Open(connection="nimforum.db", user="postgres", password="", 
            database="nimforum")

  open(s, 9000.TPort)
  while next(s):
    var r: TRequest
    r.vars = s.headers
    r.ip = r.vars["REMOTE_ADDR"]
    r.url = r.vars["DOCUMENT_URI"]
    r.startTime = epochTime()
    
    # the server software (nginx) seems to f*ck up SCGI + POST/GET, so I work
    # around this issue here:
    try:
      for key, val in cgi.decodeData(r.vars["QUERY_STRING"]):
        r.vars[key] = val
    except ECgi:
      nil
    try:
      for key, val in cgi.decodeData(s.input):
        r.vars[key] = val
    except ECgi:
      nil
    let fi = processFile(r)
    
    if fi.isFile:
      writeStatusOkTextContent(s.client, fi.contentType)
      send(s.client, fi.content)
    else:
      let (status, resp, headers) = processRequest(r)
      s.client.writeStatusContent(status, resp, headers)
    s.client.close()
  close(s)
  close(db)

proc mainWrapper() =
  for i in 0..10:
    try:
      main()
    except:
      echo "FATAL: ", getCurrentExceptionMsg()

mainWrapper()

