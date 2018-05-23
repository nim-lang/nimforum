import asyncdispatch, smtp, strutils, json, os, rst, rstgen, xmltree, strtabs,
  htmlparser, streams, parseutils, options, logging
from times import getTime, getGMTime, format

# Used to be:
# {'A'..'Z', 'a'..'z', '0'..'9', '_', '\128'..'\255'}
let
  UsernameIdent* = IdentChars # TODO: Double check that everyone follows this.

import frontend/[karaxutils, error]
export parseInt

proc `%`*[T](opt: Option[T]): JsonNode =
  ## Generic constructor for JSON data. Creates a new ``JNull JsonNode``
  ## if ``opt`` is empty, otherwise it delegates to the underlying value.
  if opt.isSome: %opt.get else: newJNull()

type
  Config* = object
    smtpAddress*: string
    smtpPort*: int
    smtpUser*: string
    smtpPassword*: string
    mlistAddress*: string
    recaptchaSecretKey*: string
    recaptchaSiteKey*: string
    isDev*: bool
    dbPath*: string
    hostname*: string
    name*, title*: string
    ga*: string
    port*: int

  ForumError* = object of Exception
    data*: PostError

proc newForumError*(message: string,
                   fields: seq[string] = @[]): ref ForumError =
  new(result)
  result.msg = message
  result.data =
    PostError(
      errorFields: fields,
      message: message
    )

var docConfig: StringTableRef

docConfig = rstgen.defaultConfig()
docConfig["doc.listing_start"] = "<pre class='code' data-lang='$2'><code>"
docConfig["doc.listing_end"] = "</code><div class='code-buttons'><button class='btn btn-primary btn-sm'>Run</button></div></pre>"

proc loadConfig*(filename = getCurrentDir() / "forum.json"): Config =
  result = Config(smtpAddress: "", smtpPort: 25, smtpUser: "",
                  smtpPassword: "", mlistAddress: "")
  let root = parseFile(filename)
  result.smtpAddress = root{"smtpAddress"}.getStr("")
  result.smtpPort = root{"smtpPort"}.getNum(25).int
  result.smtpUser = root{"smtpUser"}.getStr("")
  result.smtpPassword = root{"smtpPassword"}.getStr("")
  result.mlistAddress = root{"mlistAddress"}.getStr("")
  result.recaptchaSecretKey = root{"recaptchaSecretKey"}.getStr("")
  result.recaptchaSiteKey = root{"recaptchaSiteKey"}.getStr("")
  result.isDev = root{"isDev"}.getBool()
  result.dbPath = root{"dbPath"}.getStr("nimforum.db")
  result.hostname = root["hostname"].getStr()
  result.name = root["name"].getStr()
  result.title = root["title"].getStr()
  result.ga = root{"ga"}.getStr()
  result.port = root{"port"}.getNum(5000).int

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
    warn("Could not parse rst html.")
