import strformat, times, options, json, tables, sugar, httpcore
from dom import window, Location

include karax/prelude
import jester/patterns

import threadlist, postlist, header, profile, newthread, error, about
import resetpassword
import karaxutils

type
  State = ref object
    url: Location
    profile: ProfileState
    newThread: NewThread
    about: About
    resetPassword: ResetPassword

proc copyLocation(loc: Location): Location =
  # TODO: It sucks that I had to do this. We need a nice way to deep copy in JS.
  Location(
    hash: loc.hash,
    host: loc.host,
    hostname: loc.hostname,
    href: loc.href,
    pathname: loc.pathname,
    port: loc.port,
    protocol: loc.protocol,
    search: loc.search
  )

proc newState(): State =
  State(
    url: copyLocation(window.location),
    profile: newProfileState(),
    newThread: newNewThread(),
    about: newAbout(),
    resetPassword: newResetPassword()
  )

var state = newState()
proc onPopState(event: dom.Event) =
  # This event is usually only called when the user moves back in their
  # history. I fire it in karaxutils.anchorCB as well to ensure the URL is
  # always updated. This should be moved into Karax in the future.
  kout(kstring"New URL: ", window.location.href, " ", state.url.href)
  if state.url.href != window.location.href:
    state = newState() # Reload the state to remove stale data.
  state.url = copyLocation(window.location)

  redraw()

type Params = Table[string, string]
type
  Route = object
    n: string
    p: proc (params: Params): VNode

proc r(n: string, p: proc (params: Params): VNode): Route = Route(n: n, p: p)
proc route(routes: openarray[Route]): VNode =
  let path =
    if state.url.pathname.len == 0: "/" else: $state.url.pathname
  let prefix = if appName == "/": "" else: appName
  for route in routes:
    let pattern = (prefix & route.n).parsePattern()
    let (matched, params) = pattern.match(path)
    if matched:
      return route.p(params)

  return renderError("Unmatched route: " & path, Http500)

proc render(): VNode =
  result = buildHtml(tdiv()):
    renderHeader()
    route([
      r("/newthread",
        (params: Params) =>
          (render(state.newThread))
      ),
      r("/profile/@username",
        (params: Params) =>
          (render(state.profile, params["username"], getLoggedInUser()))
      ),
      r("/t/@id",
        (params: Params) =>
          (
            let postId = getInt(($state.url.hash).substr(1), 0);
            renderPostList(
              params["id"].parseInt(),
              if postId == 0: none[int]() else: some[int](postId),
              getLoggedInUser()
            )
          )
      ),
      r("/about/?@page?",
        (params: Params) => (render(state.about, params["page"]))
      ),
      r("/activateEmail/success",
        (params: Params) => (
          renderMessage(
            "Email activated",
            "You can now create new posts!",
            "fa-check"
          )
        )
      ),
      r("/activateEmail/failure",
        (params: Params) => (
          renderMessage(
            "Email activation failed",
            "Couldn't verify the supplied ident",
            "fa-exclamation"
          )
        )
      ),
      r("/resetPassword/success",
        (params: Params) => (
          renderMessage(
            "Password changed",
            "You can now login using your new password!",
            "fa-check"
          )
        )
      ),
      r("/resetPassword",
        (params: Params) => (
          render(state.resetPassword)
        )
      ),
      r("/404",
        (params: Params) => render404()
      ),
      r("/", (params: Params) => renderThreadList(getLoggedInUser()))
    ])

window.onPopState = onPopState
setRenderer render