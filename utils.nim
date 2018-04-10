import asyncdispatch, smtp, strutils, json, os, rst, rstgen, xmltree, strtabs,
  htmlparser, streams, parseutils, db_sqlite
from times import getTime, getGMTime, format

proc parseInt*(s: string, value: var int, validRange: Slice[int]) {.
  noSideEffect.} =
  ## parses `s` into an integer in the range `validRange`. If successful,
  ## `value` is modified to contain the result. Otherwise no exception is
  ## raised and `value` is not touched; this way a reasonable default value
  ## won't be overwritten.
  var x = value
  try:
    discard parseutils.parseInt(s, x, 0)
  except OverflowError:
    discard
  if x in validRange: value = x

type
  Config* = object
    smtpAddress: string
    smtpPort: int
    smtpUser: string
    smtpPassword: string
    mlistAddress: string
    recaptchaSecretKey*: string
    recaptchaSiteKey*: string

var docConfig: StringTableRef

docConfig = rstgen.defaultConfig()
docConfig["doc.listing_start"] = "<pre class=\"listing $2\">"
docConfig["doc.smiley_format"] = "/images/smilieys/$1.png"

proc loadConfig*(filename = getCurrentDir() / "forum.json"): Config =
  result = Config(smtpAddress: "", smtpPort: 25, smtpUser: "",
                  smtpPassword: "", mlistAddress: "")
  try:
    let root = parseFile(filename)
    result.smtpAddress = root{"smtpAddress"}.getStr("")
    result.smtpPort = root{"smtpPort"}.getNum(25).int
    result.smtpUser = root{"smtpUser"}.getStr("")
    result.smtpPassword = root{"smtpPassword"}.getStr("")
    result.mlistAddress = root{"mlistAddress"}.getStr("")
    result.recaptchaSecretKey = root{"recaptchaSecretKey"}.getStr("")
    result.recaptchaSiteKey = root{"recaptchaSiteKey"}.getStr("")
  except:
    echo("[WARNING] Couldn't read config file: ", filename)

proc processGT(n: XmlNode, tag: string): (int, XmlNode, string) =
  result = (0, newElement(tag), tag)
  if n.kind == xnElement and len(n) == 1 and n[0].kind == xnElement:
    return processGT(n[0], if n[0].kind == xnElement: n[0].tag else: tag)

  var countGT = true
  for c in items(n):
    case c.kind
    of xnText:
      if c.text == ">" and countGT:
        result[0].inc()
      else:
        countGT = false
        result[1].add(newText(c.text))
    else:
      result[1].add(c)

proc blockquoteFinish(currentBlockquote, newNode: var XmlNode, n: XmlNode) =
  if currentBlockquote.len > 0:
    #echo(currentBlockquote.repr)
    newNode.add(currentBlockquote)
    currentBlockquote = newElement("blockquote")
  newNode.add(n)

proc rstToHtml*(content: string): string =
  result = rstgen.rstToHtml(content, {roSupportSmilies, roSupportMarkdown},
                            docConfig)
  # Bolt on quotes.
  # TODO: Yes, this is ugly. I wrote it quickly. PRs welcome ;)
  try:
    var node = parseHtml(newStringStream(result))
    var newNode = newElement("div")
    if node.kind == xnElement:
      var currentBlockquote = newElement("blockquote")
      for n in items(node):
        case n.kind
        of xnElement:
          case n.tag
          of "p":
            let (nesting, contentNode, tag) = processGT(n, "p")
            if nesting > 0:
              var bq = currentBlockquote
              for i in 1 .. <nesting:
                var newBq = bq.child("blockquote")
                if newBq.isNil:
                  newBq = newElement("blockquote")
                  bq.add(newBq)
                bq = newBq
              bq.insert(contentNode, if bq.len == 0: 0 else: bq.len)
            else:
              blockquoteFinish(currentBlockquote, newNode, n)
          else:
            blockquoteFinish(currentBlockquote, newNode, n)
        of xnText:
          if n.text[0] == '\10':
            newNode.add(n)
          else:
            blockquoteFinish(currentBlockquote, newNode, n)
        else:
          blockquoteFinish(currentBlockquote, newNode, n)
      result = $newNode
  except:
    echo("[WARNING] Could not parse rst html.")

proc sendMail(config: Config, subject, message, recipient: string, from_addr = "forum@nim-lang.org", otherHeaders:seq[(string, string)] = @[]) {.async.} =
  if config.smtpAddress.len == 0:
    echo("[WARNING] Cannot send mail: no smtp server configured (smtpAddress).")
    return

  var client = newAsyncSmtp()
  await client.connect(config.smtpAddress, Port(config.smtpPort))
  if config.smtpUser.len > 0:
    await client.auth(config.smtpUser, config.smtpPassword)

  let toList = @[recipient]

  var headers = otherHeaders
  headers.add(("From", from_addr))

  let encoded = createMessage(subject, message,
      toList, @[], headers)

  await client.sendMail(from_addr, toList, $encoded)

proc sendMailToMailingList*(config: Config, username, user_email_addr, subject, message: string, threadUrl: string, thread_id=0, post_id=0, is_reply=false) {.async.} =
  # send message to a mailing list
  if config.mlistAddress.len == 0:
    echo("[WARNING] Cannot send mail: no mlistAddress configured.")
    return

  let from_addr = "$# <$#>" % [username, user_email_addr]

  let date = getTime().getGMTime().format("ddd, d MMM yyyy HH:mm:ss") & " +0000"
  var otherHeaders = @[
    ("Date", date),
    ("Resent-From", "forum@nim-lang.org"),
    ("Resent-date", date)
  ]

  if is_reply:
    let msg_id = "<forum-id-$#-$#@nim-lang.org>" % [$thread_id, $post_id]
    otherHeaders.add(("Message-ID", msg_id))
    let references = "<forum-tid-$#@nim-lang.org>" % [$thread_id]
    otherHeaders.add(("References", references))

  else:  # New thread
    let msg_id = "<forum-tid-$#@nim-lang.org>" % $thread_id
    otherHeaders.add(("Message-ID", msg_id))

  var processedMsg: string
  try:
    processedMsg = rstToHTML(message) & "<hr/><a href=\"" & threadUrl & "\" style=\"font-size:small\">View thread on Nim forum</a>"
    otherHeaders.add(("Content-Type", "text/html; charset=\"UTF-8\""))
  except:
    processedMsg = message

  await sendMail(config, subject, processedMsg, config.mlistAddress, from_addr=from_addr, otherHeaders=otherHeaders)

proc sendPassReset*(config: Config, email, user, resetUrl: string) {.async.} =
  let message = """Hello $1,
A password reset has been requested for your account on the Nim Forum.

If you did not make this request, you can safely ignore this email.
A password reset request can be made by anyone, and it does not indicate
that your account is in any danger of being accessed by someone else.

If you do actually want to reset your password, visit this link:

  $2

Thank you for being a part of the Nim community!""" % [user, resetUrl]
  await sendMail(config, "Nim Forum Password Recovery", message, email)

proc sendEmailActivation*(config: Config, email, user, activateUrl: string) {.async.} =
  let message = """Hello $1,
You have recently registered an account on the Nim Forum.

As the final step in your registration, we require that you confirm your email
via the following link:

  $2

Thank you for registering and becoming a part of the Nim community!""" % [user, activateUrl]
  await sendMail(config, "Nim Forum Account Email Confirmation", message, email)



proc pageNumber(postCount: int): int =
  ## Find current page number
  ##
  ## Proc needs to be redefined. It does only support
  ## up to 20 pages. Otherwise it just takes the first
  ## two first digits. This will lead to a wrong page (-1)
  ## at. 191, 201, etc.
  case postCount
  of 1..10: return 1
  of 11..20:  return 2
  of 21..30: return 3
  of 31..40: return 4
  of 41..50: return 5
  of 51..60: return 6
  of 61..70: return 7
  of 71..80: return 8
  of 81..90: return 9
  of 91..100: return 10
  of 101..110: return 11
  of 111..120: return 12
  of 121..130: return 13
  of 131..140: return 14
  of 141..150: return 15
  of 151..160: return 16  
  of 161..170: return 17  
  of 171..180: return 18
  of 181..190: return 19  
  of 191..200: return 20  
  else: return parseInt(($postCount).substr(0,1))


proc sendEmailNewReply*(db: DbConn, config: Config, userID, userName, threadID, postID: string) {.async.} =
  ## Send email to user with a new reply, to a thread they follow.
  ## This only applies to users, who actively has enabled this feature.

  let userNotify = getAllRows(db, sql"SELECT DISTINCT person.id, person.email FROM post LEFT JOIN person ON person.id = post.author WHERE person.mailNewComment = ? AND post.thread = ?;", "1", threadID)

  if userNotify.len() == 0:
    return

  let postInfo = getRow(db, sql"SELECT thread.name,	post.content, person.name, post.creation, (SELECT count(DISTINCT post.id) FROM post WHERE thread = ?) AS numberOfPosts FROM post LEFT JOIN thread ON thread.id = post.thread LEFT JOIN person ON person.id = post.author WHERE thread.id = ? AND post.id = ?", threadID, threadID, postID)

  var pageNumber = pageNumber(parseInt(postInfo[4]))

  let message = """Hello $6,

There is a new reply to thread you are following. There are now $5 replies in total.

Thread: <a href="www.forum.nim-lang.org/t/$7/$9#$8">$1</a>

New reply:
- Author: $3
- Creation: $4
- Reply:
$2

---
Thank you for being a part of the Nim community!""" % [postInfo[0], postInfo[1], postInfo[2], postInfo[3], postInfo[4], userName, threadID, postID, $pageNumber]

  for userEmail in userNotify:
    if userEmail[0] == userID:  # If user matches the author, then skip the mail
      continue

    await sendMail(config, "Nim Forum New reply on " & postInfo[0].substr(0,50), message, userEmail[1])
    await sleepAsync(200)