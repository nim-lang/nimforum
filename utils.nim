import asyncdispatch, smtp, strutils, json, os
from times import getTime, getGMTime, format

type
  Config* = object
    smtpAddress: string
    smtpPort: int
    smtpUser: string
    smtpPassword: string
    mlistAddress: string

proc loadConfig*(filename = getCurrentDir() / "forum.json"): Config =
  result = Config(smtpAddress: "localhost", smtpPort: 25, smtpUser: "",
                  smtpPassword: "")
  try:
    let root = parseFile(filename)
    result.smtpAddress = root["smtpAddress"].getStr("localhost")
    result.smtpPort = root["smtpPort"].getNum(25).int
    result.smtpUser = root["smtpUser"].getStr("")
    result.smtpPassword = root["smtpPassword"].getStr("")
    result.mlistAddress = root["mlistAddress"].getStr("")
  except:
    echo("[WARNING] Couldn't read config file: ./forum.json")

proc sendMail(config: Config, subject, message, recipient: string, from_addr = "forum@nim-lang.org", otherHeaders:seq[(string, string)] = @[]) {.async.} =
  var client = newAsyncSmtp(config.smtpAddress, Port(config.smtpPort))
  await client.connect()
  if config.smtpUser.len > 0:
    await client.auth(config.smtpUser, config.smtpPassword)

  let toList = @[recipient]

  var headers = otherHeaders
  headers.add(("From", from_addr))

  let encoded = createMessage(subject, message,
      toList, @[], headers)

  await client.sendMail(from_addr, toList, $encoded)

proc sendMailToMailingList*(config: Config, username, user_email_addr, subject, message: string, thread_id=0, post_id=0, is_reply=false) {.async.} =
  # send message to a mailing list
  if config.mlistAddress == "":
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

  await sendMail(config, subject, message, config.mlistAddress, from_addr=from_addr, otherHeaders=otherHeaders)

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
