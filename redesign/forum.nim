import strformat, times, options, json, tables, sugar
from dom import window, Location

include karax/prelude
import jester/patterns

import threadlist, postlist, header
import karaxutils

type
  State = ref object
    url: Location

proc newState(): State =
  State(
    url: window.location
  )

var state = newState()
proc onPopState(event: dom.Event) =
  # This event is usually only called when the user moves back in their
  # history. I fire it in karaxutils.anchorCB as well to ensure the URL is
  # always updated. This should be moved into Karax in the future.
  kout(kstring"New URL: ", window.location.href)
  state.url = window.location
  redraw()

const appName = "/karax"
type Params = Table[string, string]
type
  Route = object
    n: string
    p: proc (params: Params): VNode

proc r(n: string, p: proc (params: Params): VNode): Route = Route(n: n, p: p)
proc route(routes: openarray[Route]): VNode =
  for route in routes:
    let pattern = (appName & route.n).parsePattern()
    let (matched, params) = pattern.match($state.url.pathname)
    if matched:
      return route.p(params)

proc render(): VNode =
  result = buildHtml(tdiv()):
    renderHeader()
    route([
      r("/t/@id?",
        (params: Params) =>
          (kout(params["id"].cstring);
          renderPostList(params["id"].parseInt(), false))
      ),
      r("/", (params: Params) => renderThreadList())
    ])

window.onPopState = onPopState
setRenderer render