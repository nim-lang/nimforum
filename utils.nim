import asyncdispatch, smtp, strutils, json, os
from times import getTime, getGMTime, format
import pop3
from net import Port
import tables


type
  Config* = object
    smtpAddress: string
    smtpPort: int
    smtpUser: string
    smtpPassword: string
    mlistAddress: string
    popAddress: string
    popPort: Port
    popUser: string
    popPassword: string
    popDeleteOnIngest: bool
    popAuth: string
    popTLS: bool

proc debug(msg: string): void =
  echo "DEBUG: $#" % msg

proc info(msg: string): void =
  echo "INFO: $#" % msg

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

    result.popAddress = root["pop"]["Address"].getStr("")
    result.popPort = root["pop"]["Port"].getNum(110).Port
    result.popUser = root["pop"]["User"].getStr("")
    result.popPassword = root["pop"]["Password"].getStr("")
    result.popDeleteOnIngest = root["pop"]["DeleteOnIngest"].getBVal(true)
    result.popAuth = root["pop"]["Auth"].getStr("")
    result.popTLS = root["pop"]["TLS"].getBVal(true)
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

proc ltrim(s: string, n: int): string =
  s[n..<len(s)]

type EmailMessage = tuple
  headers: OrderedTableRef[string, string]
  body: seq[string]

proc fetch_pop3_message(client: POP3Client, msg_num: int): EmailMessage =
  ## Fetch an email message using POP3
  # https://tools.ietf.org/html/rfc2822
  var body = client.retr(msg_num=msg_num)[1]
  body = body.map(proc(x: string): string = x.strip(leading=false))

  var folding_buffer: seq[string] = @[]
  var field_name = ""
  var header_lines_len = 0
  var headers = newOrderedTable[string, string]()
  for line in body:
    if line == "":  # end of header block
      headers[field_name] = folding_buffer.join("")
      break

    if line[0] in [' ', '\t']:
      # folding detected
      folding_buffer.add line.strip()

    else:
      # new field name
      if field_name != "":
        headers[field_name] = folding_buffer.join("")
        folding_buffer = @[]

      let colon_pos = line.find(':')
      if colon_pos == -1:
        echo "Unexpected header line: $#" % line
        break
      field_name = line[0..<colon_pos].toLower

      folding_buffer.add line[(colon_pos+1)..<len(line)].strip()

    header_lines_len.inc()

  body = body[(header_lines_len+1)..<len(body)]

  result = (headers, body)


iterator fetch_pop3_messages*(client: POP3Client): EmailMessage =
  ## Fetch all available emails from POP3
  let num_emails = client.stat().numMessages
  debug "$# messages to fetch" % $num_emails
  for n in 1..num_emails:
    yield client.fetch_pop3_message(n)

proc connect_to_POP3*(conf: Config): POP3Client =
  ## Connect to a POP3 server
  result = newPOP3Client(host=conf.popAddress, port=conf.popPort,
    use_ssl=conf.popTLS)
  # TODO: implement popAuth string
  result.user(conf.popUser)
  result.pass(conf.popPassword)

