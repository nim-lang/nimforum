import asyncdispatch, smtp, strutils, json, os, rst, rstgen, xmltree, strtabs,
  htmlparser, streams, parseutils, options
from times import getTime, getGMTime, format

# Used to be:
# {'A'..'Z', 'a'..'z', '0'..'9', '_', '\128'..'\255'}
let
  UsernameIdent* = IdentChars # TODO: Double check that everyone follows this.

import redesign/karaxutils
export parseInt

proc `%`*[T](opt: Option[T]): JsonNode =
  ## Generic constructor for JSON data. Creates a new ``JNull JsonNode``
  ## if ``opt`` is empty, otherwise it delegates to the underlying value.
  if opt.isSome: %opt.get else: newJNull()

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
docConfig["doc.listing_start"] = "<pre class='code' data-lang='$2'><code>"
docConfig["doc.listing_end"] = "</code><div class='code-buttons'><button class='btn btn-primary btn-sm'>Run</button></div></pre>"

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

proc processQuotes(node: XmlNode): XmlNode =
  # Bolt on quotes.
  # TODO: Yes, this is ugly. I wrote it quickly. PRs welcome ;)
  result = newElement("div")
  var currentBlockquote = newElement("blockquote")
  for n in items(node):
    case n.kind
    of xnElement:
      case n.tag
      of "p":
        let (nesting, contentNode, _) = processGT(n, "p")
        if nesting > 0:
          var bq = currentBlockquote
          for i in 1 ..< nesting:
            var newBq = bq.child("blockquote")
            if newBq.isNil:
              newBq = newElement("blockquote")
              bq.add(newBq)
            bq = newBq
          bq.add(contentNode)
        else:
          blockquoteFinish(currentBlockquote, result, n)
      else:
        blockquoteFinish(currentBlockquote, result, n)
    of xnText:
      if n.text[0] == '\10':
        result.add(n)
      else:
        blockquoteFinish(currentBlockquote, result, n)
    else:
      blockquoteFinish(currentBlockquote, result, n)

proc replaceMentions(node: XmlNode): seq[XmlNode] =
  assert node.kind == xnText
  result = @[]

  var current = ""
  var i = 0
  while i < len(node.text):
    i += parseUntil(node.text, current, {'@'}, i)
    if i >= len(node.text): break
    if node.text[i] == '@':
      i.inc # Skip @
      var username = ""
      i += parseWhile(node.text, username, UsernameIdent, i)

      if username.len == 0:
        result.add(newText(current & "@"))
      else:
        let el = <>span(
          class="user-mention",
          data-username=username,
          newText("@" & username)
        )

        result.add(newText(current))
        current = ""
        result.add(el)

  result.add(newText(current))

proc processMentions(node: XmlNode): XmlNode =
  case node.kind
  of xnText:
    result = newElement("span")
    for child in replaceMentions(node):
      result.add(child)
  of xnElement:
    case node.tag
    of "pre", "code", "tt":
      return node
    else:
      result = newElement(node.tag)
      result.attrs = node.attrs
      for n in items(node):
        result.add(processMentions(n))
  else:
    return node

proc rstToHtml*(content: string): string =
  result = rstgen.rstToHtml(content, {roSupportMarkdown},
                            docConfig)
  try:
    var node = parseHtml(newStringStream(result))
    if node.kind == xnElement:
      node = processQuotes(node)
    node = processMentions(node)
    result = ""
    add(result, node, indWidth=0, addNewLines=false)
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
