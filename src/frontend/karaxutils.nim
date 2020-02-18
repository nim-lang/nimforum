import strutils, strformat, parseutils, tables

proc limit*(str: string, n: int): string =
  ## Limit the number of characters in a string. Ends with a elipsis
  if str.len > n:
    return str[0..<n-3] & "..."
  else:
    return str

proc slug*(name: string): string =
  ## Transforms text into a url slug
  name.strip().replace(" ", "-").toLowerAscii

proc parseIntSafe*(s: string, value: var int) {.noSideEffect.} =
  ## parses `s` into an integer in the range `validRange`. If successful,
  ## `value` is modified to contain the result. Otherwise no exception is
  ## raised and `value` is not touched; this way a reasonable default value
  ## won't be overwritten.
  try:
    discard parseutils.parseInt(s, value, 0)
  except OverflowError:
    discard

proc getInt*(s: string, default = 0): int =
  ## Safely parses an int and returns it.
  result = default
  parseIntSafe(s, result)

proc getInt64*(s: string, default = 0): int64 =
  ## Safely parses an int and returns it.
  result = default
  try:
    discard parseutils.parseBiggestInt(s, result, 0)
  except OverflowError:
    discard

when defined(js):
  include karax/prelude
  import karax / [kdom, kajax]

  from dom import nil

  const appName* = "/"

  proc class*(classes: varargs[tuple[name: string, present: bool]],
             defaultClasses: string = ""): string =
    result = defaultClasses & " "
    for class in classes:
      if class.present: result.add(class.name & " ")

  proc makeUri*(relative: string, appName=appName, includeHash=false,
                search: string=""): string =
    ## Concatenates ``relative`` to the current URL in a way that is
    ## (possibly) sane.
    var relative = relative
    assert appName in $window.location.pathname
    if relative[0] == '/': relative = relative[1..^1]

    return $window.location.protocol & "//" &
            $window.location.host &
            appName &
            relative &
            search &
            (if includeHash: $window.location.hash else: "")

  proc makeUri*(relative: string, params: varargs[(string, string)],
                appName=appName, includeHash=false,
                reuseSearch=true): string =
    var query = ""
    for i in 0 ..< params.len:
      let param = params[i]
      if i != 0: query.add("&")
      query.add(param[0] & "=" & param[1])

    if query.len > 0:
      var search = if reuseSearch: $window.location.search else: ""
      if search.len != 0: search.add("&")
      search.add(query)
      if search[0] != '?': search = "?" & search
      makeUri(relative, appName, search=search)
    else:
      makeUri(relative, appName)

  proc navigateTo*(uri: cstring) =
    # TODO: This was annoying. Karax also shouldn't have its own `window`.
    dom.pushState(dom.window.history, 0, cstring"", uri)

    # Fire the popState event.
    dom.dispatchEvent(dom.window, dom.newEvent("popstate"))

  proc anchorCB*(e: Event, n: VNode) =
    let mE = e.MouseEvent
    if not (mE.metaKey or mE.ctrlKey):
      e.preventDefault()

      # TODO: Why does Karax have it's own Node type? That's just silly.
      let url = n.getAttr("href")

      navigateTo(url)
      window.location.href = url

  proc newFormData*(form: dom.Element): FormData
    {.importcpp: "new FormData(@)", constructor.}
  proc get*(form: FormData, key: cstring): cstring
    {.importcpp: "#.get(@)".}

  proc renderProfileUrl*(username: string): string =
    makeUri(fmt"/profile/{username}")

  proc renderPostUrl*(threadId, postId: int): string =
    makeUri(fmt"/t/{threadId}#{postId}")

  proc parseUrlQuery*(query: string, result: var Table[string, string])
    {.deprecated: "use stdlib".} =
    ## Based on copy from Jester. Use stdlib when
    ## https://github.com/nim-lang/Nim/pull/7761 is merged.
    var i = 0
    i = query.skip("?")
    while i < query.len()-1:
      var key = ""
      var val = ""
      i += query.parseUntil(key, '=', i)
      if query[i] != '=':
        raise newException(ValueError, "Expected '=' at " & $i &
                           " but got: " & $query[i])
      inc(i) # Skip =
      i += query.parseUntil(val, '&', i)
      inc(i) # Skip &
      result[$decodeUri(key)] = $decodeUri(val)
