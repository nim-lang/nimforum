import asyncdispatch, smtp, strutils, times, cgi, tables, logging

from jester import Request, makeUri

import utils, auth

type
  Mailer* = ref object
    config: Config
    lastReset: Time
    emailsSent: CountTable[string]

proc newMailer*(config: Config): Mailer =
  Mailer(
    config: config,
    lastReset: getTime(),
    emailsSent: initCountTable[string]()
  )

proc rateCheck(mailer: Mailer, address: string): bool =
  ## Returns true if we've emailed the address too much.
  let diff = getTime() - mailer.lastReset
  if diff.inHours >= 1:
    mailer.lastReset = getTime()
    mailer.emailsSent.clear()

  result = address in mailer.emailsSent and mailer.emailsSent[address] >= 2
  mailer.emailsSent.inc(address)

proc sendMail(
  mailer: Mailer,
  subject, message, recipient: string,
  otherHeaders:seq[(string, string)] = @[]
) {.async.} =
  # Ensure we aren't emailing this address too much.
  if rateCheck(mailer, recipient):
    let msg = "Too many messages have been sent to this email address recently."
    raise newForumError(msg)

  if mailer.config.smtpAddress.len == 0:
    warn("Cannot send mail: no smtp server configured (smtpAddress).")
    return
  if mailer.config.smtpFromAddr.len == 0:
    warn("Cannot send mail: no smtp from address configured (smtpFromAddr).")
    return

  var client = newAsyncSmtp()
  await client.connect(mailer.config.smtpAddress, Port(mailer.config.smtpPort))
  if mailer.config.smtpUser.len > 0:
    await client.auth(mailer.config.smtpUser, mailer.config.smtpPassword)

  let toList = @[recipient]

  var headers = otherHeaders
  headers.add(("From", mailer.config.smtpFromAddr))

  let encoded = createMessage(subject, message,
      toList, @[], headers)

  await client.sendMail(mailer.config.smtpFromAddr, toList, $encoded)

proc sendPassReset(mailer: Mailer, email, user, resetUrl: string) {.async.} =
  let message = """Hello $1,
A password reset has been requested for your account on the $3.

If you did not make this request, you can safely ignore this email.
A password reset request can be made by anyone, and it does not indicate
that your account is in any danger of being accessed by someone else.

If you do actually want to reset your password, visit this link:

  $2

Thank you for being a part of our community!
""" % [user, resetUrl, mailer.config.name]

  let subject = mailer.config.name & " Password Recovery"
  await sendMail(mailer, subject, message, email)

proc sendEmailActivation(
  mailer: Mailer,
  email, user, activateUrl: string
) {.async.} =
  let message = """Hello $1,
You have recently registered an account on the $3.

As the final step in your registration, we require that you confirm your email
via the following link:

  $2

Thank you for registering and becoming a part of our community!
""" % [user, activateUrl, mailer.config.name]
  let subject = mailer.config.name & " Account Email Confirmation"
  await sendMail(mailer, subject, message, email)

type
  SecureEmailKind* = enum
    ActivateEmail, ResetPassword

proc sendSecureEmail*(
  mailer: Mailer,
  kind: SecureEmailKind, req: Request,
  name, password, email, salt: string
) {.async.} =
  let epoch = int(epochTime())

  let path =
    case kind
    of ActivateEmail:
      "activateEmail"
    of ResetPassword:
      "resetPassword"
  let url = req.makeUri(
    "/$#?nick=$#&epoch=$#&ident=$#" %
      [
        path,
        encodeUrl(name),
        encodeUrl($epoch),
        encodeUrl(makeIdentHash(name, password, epoch, salt))
      ]
  )

  debug(url)

  let emailSentFut =
    case kind
    of ActivateEmail:
      sendEmailActivation(mailer, email, name, url)
    of ResetPassword:
      sendPassReset(mailer, email, name, url)
  yield emailSentFut
  if emailSentFut.failed:
    warn("Couldn't send email: ", emailSentFut.error.msg)
    if emailSentFut.error of ForumError:
      raise emailSentFut.error
    else:
      raise newForumError("Couldn't send email", @["email"])
