import asyncdispatch, smtp, strutils, json, os

type
  Config* = object
    smtpAddress: string
    smtpPort: int
    smtpUser: string
    smtpPassword: string

proc loadConfig*(filename = getCurrentDir() / "forum.json"): Config =
  result = Config(smtpAddress: "localhost", smtpPort: 25, smtpUser: "",
                  smtpPassword: "")
  try:
    let root = parseFile(filename)
    result.smtpAddress = root["smtpAddress"].getStr("localhost")
    result.smtpPort = root["smtpPort"].getNum(25).int
    result.smtpUser = root["smtpUser"].getStr("")
    result.smtpPassword = root["smtpPassword"].getStr("")
  except:
    echo("[WARNING] Couldn't read config file: ./forum.json")

proc sendMail(config: Config, subject, message, recipient: string) {.async.} =
  var client = newAsyncSmtp(config.smtpAddress, Port(config.smtpPort))
  await client.connect()
  if config.smtpUser.len > 0:
    await client.auth(config.smtpUser, config.smtpPassword)

  let toList = @[recipient]
  let encoded = createMessage(subject, message,
      toList, @[], [])

  await client.sendMail("forum@nim-lang.org", toList,
      $encoded)

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
