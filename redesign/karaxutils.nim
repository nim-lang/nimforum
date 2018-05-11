import strutils
import dom except window

include karax/prelude
import karax / [kdom]

const appName = "/karax/"

proc class*(classes: varargs[tuple[name: string, present: bool]],
           defaultClasses: string = ""): string =
  result = defaultClasses & " "
  for class in classes:
    if class.present: result.add(class.name & " ")

proc makeUri*(relative: string, appName=appName): string =
  ## Concatenates ``relative`` to the current URL in a way that is sane.
  var relative = relative
  assert appName in $window.location.pathname
  if relative[0] == '/': relative = relative[1..^1]

  return $window.location.protocol & "//" &
          $window.location.host &
          appName &
          relative &
          $window.location.search &
          $window.location.hash

proc makeUri*(relative: string, params: varargs[(string, string)],
              appName=appName): string =
  var query = ""
  for i in 0 ..< params.len:
    let param = params[i]
    if i != 0: query.add("&")
    query.add(param[0] & "=" & param[1])

  if query.len > 0:
    makeUri(relative & "?" & query, appName)
  else:
    makeUri(relative, appName)

proc anchorCB*(e: kdom.Event, n: VNode) = # TODO: Why does this need disamb?
  e.preventDefault()

  # TODO: Why does Karax have it's own Node type? That's just silly.
  let url = cast[dom.Node](n.dom).getAttribute(cstring"href")

  # TODO: This was annoying. Karax also shouldn't have its own `window`.
  dom.pushState(dom.window.history, 5, cstring"Thread", url)

  # Fire the popState event.
  dom.window.dispatchEvent(newEvent("popstate"))


type
  FormData* = ref object
proc newFormData*(form: dom.Element): FormData
  {.importcpp: "new FormData(@)", constructor.}
proc get*(form: FormData, key: cstring): cstring
  {.importcpp: "#.get(@)".}