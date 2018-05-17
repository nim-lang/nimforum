import strutils, options, strformat, parseutils

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

proc getInt*(s: string, default = 0): int =
  ## Safely parses an int and returns it.
  result = default
  parseInt(s, result, 0..1_000_000_000)

when defined(js):
  include karax/prelude
  import karax / [kdom]

  import dom except window

  const appName = "/karax/"

  proc class*(classes: varargs[tuple[name: string, present: bool]],
             defaultClasses: string = ""): string =
    result = defaultClasses & " "
    for class in classes:
      if class.present: result.add(class.name & " ")

  proc makeUri*(relative: string, appName=appName, includeHash=false): string =
    ## Concatenates ``relative`` to the current URL in a way that is
    ## (possibly) sane.
    var relative = relative
    assert appName in $window.location.pathname
    if relative[0] == '/': relative = relative[1..^1]

    return $window.location.protocol & "//" &
            $window.location.host &
            appName &
            relative &
            $window.location.search &
            (if includeHash: $window.location.hash else: "")

  proc makeUri*(relative: string, params: varargs[(string, string)],
                appName=appName, includeHash=false): string =
    var query = ""
    for i in 0 ..< params.len:
      let param = params[i]
      if i != 0: query.add("&")
      query.add(param[0] & "=" & param[1])

    if query.len > 0:
      makeUri(relative & "?" & query, appName)
    else:
      makeUri(relative, appName)

  proc navigateTo*(uri: cstring) =
    # TODO: This was annoying. Karax also shouldn't have its own `window`.
    dom.pushState(dom.window.history, 0, cstring"", uri)

    # Fire the popState event.
    dom.window.dispatchEvent(newEvent("popstate"))

  proc anchorCB*(e: kdom.Event, n: VNode) = # TODO: Why does this need disamb?
    e.preventDefault()

    # TODO: Why does Karax have it's own Node type? That's just silly.
    let url = cast[dom.Node](n.dom).getAttribute(cstring"href")

    navigateTo(url)

  type
    FormData* = ref object
  proc newFormData*(): FormData
    {.importcpp: "new FormData()", constructor.}
  proc newFormData*(form: dom.Element): FormData
    {.importcpp: "new FormData(@)", constructor.}
  proc get*(form: FormData, key: cstring): cstring
    {.importcpp: "#.get(@)".}
  proc append*(form: FormData, key, val: cstring)
    {.importcpp: "#.append(@)".}

  proc renderProfileUrl*(username: string): string =
    makeUri(fmt"/profile/{username}")

  proc renderPostUrl*(threadId, postId: int): string =
    makeUri(fmt"/t/{threadId}#{postId}")