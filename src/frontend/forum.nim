import strformat, times, options, json, tables, sugar, httpcore, uri
from dom import window, Location, document, decodeURI

include karax/prelude
import jester/[patterns]

import threadlist, postlist, header, profile, newthread, error, about
import resetpassword, activateemail, search
import karaxutils

type
  State = ref object
    originalTitle: cstring
    url: Location
    profile: ProfileState
    newThread: NewThread
    about: About
    resetPassword: ResetPassword
    activateEmail: ActivateEmail
    search: Search

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
    originalTitle: document.title,
    url: copyLocation(window.location),
    profile: newProfileState(),
    newThread: newNewThread(),
    about: newAbout(),
    resetPassword: newResetPassword(),
    activateEmail: newActivateEmail(),
    search: newSearch()
  )

var state = newState()
proc onPopState(event: dom.Event) =
  # This event is usually only called when the user moves back in their
  # history. I fire it in karaxutils.anchorCB as well to ensure the URL is
  # always updated. This should be moved into Karax in the future.
  echo "New URL: ", window.location.href, " ", state.url.href
  document.title = state.originalTitle
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
    var (matched, params) = pattern.match(path)
    parseUrlQuery($state.url.search, params)
    if matched:
      return route.p(params)

  return renderError("Unmatched route: " & path, Http500)

proc render(): VNode =
  result = buildHtml(tdiv()):
    renderHeader()
    route([
      r("/newthread",
        (params: Params) =>
          (render(state.newThread, getLoggedInUser()))
      ),
      r("/profile/@username",
        (params: Params) =>
          (
            render(
              state.profile,
              decodeURI(params["username"]),
              getLoggedInUser()
            )
          )
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
      r("/activateEmail",
        (params: Params) => (
          render(state.activateEmail)
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
      r("/search",
        (params: Params) => (
          render(state.search, params["q"], getLoggedInUser())
        )
      ),
      r("/404",
        (params: Params) => render404()
      ),
      r("/", (params: Params) => renderThreadList(getLoggedInUser()))
    ])

window.onPopState = onPopState
setRenderer render
