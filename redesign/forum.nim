import strformat, times, options, json, tables, future
from dom import window, Location

include karax/prelude
import jester/patterns

import threadlist, postlist, karaxutils

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

proc genHeader(): VNode =
  result = buildHtml(tdiv()):
    header(id="main-navbar"):
      tdiv(class="navbar container grid-xl"):
        section(class="navbar-section"):
          a(href=makeUri("/")):
            img(src="images/crown.png", id="img-logo") # TODO: Customisation.
        section(class="navbar-section"):
          tdiv(class="input-group input-inline"):
            input(class="search-input input-sm", `type`="text", placeholder="search")
          a(href="#signup-modal", id="signup-btn"):
            button(class="btn btn-primary btn-sm"):
              italic(class="fas fa-user-plus")
              text " Sign up"
          a(href="#login-modal", id="login-btn"):
            button(class="btn btn-primary btn-sm"):
              italic(class="fas fa-sign-in-alt")
              text " Log in"

    # Modals
    tdiv(class="modal modal-sm", id="login-modal"):
      a(href="#", class="modal-overlay", "aria-label"="close")
      tdiv(class="modal-container"):
        tdiv(class="modal-header"):
          a(href="#", class="btn btn-clear float-right", "aria-label"="close")
          tdiv(class="modal-title h5"):
            text "Log in"
        tdiv(class="modal-body"):
          tdiv(class="content"):
            form():
              tdiv(class="form-group"):
                label(class="form-label", `for`="username"):
                  text "Username"
                input(class="form-input", `type`="text", id="username")
              tdiv(class="form-group"):
                label(class="form-label", `for`="password"):
                  text "Password"
                input(class="form-input", `type`="password", id="password")
            button(class="btn btn-link"):
              text "Reset your password"
        tdiv(class="modal-footer"):
          button(class="btn btn-primary"):
            text "Log in"
          a(href="#signup-modal"):
            button(class="btn"):
              text "Create account"

    tdiv(class="modal", id="signup-modal"):
      a(href="#", class="modal-overlay", "aria-label"="close")
      tdiv(class="modal-container"):
        tdiv(class="modal-header"):
          a(href="#", class="btn btn-clear float-right", "aria-label"="close")
          tdiv(class="modal-title h5"):
            text "Create a new account"
        tdiv(class="modal-body"):
          tdiv(class="content"):
            form():
              tdiv(class="form-group"):
                label(class="form-label", `for`="email"):
                  text "Email"
                input(class="form-input", `type`="text", id="email")
              tdiv(class="form-group"):
                label(class="form-label", `for`="username"):
                  text "Username"
                input(class="form-input", `type`="text", id="username")
              tdiv(class="form-group"):
                label(class="form-label", `for`="password"):
                  text "Password"
                input(class="form-input", `type`="password", id="password")
        tdiv(class="modal-footer"):
          button(class="btn btn-primary"):
            text "Create account"
          a(href="#login-modal"):
            button(class="btn"):
              text "Log in"


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
    genHeader()
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