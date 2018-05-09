import strformat, times, options, json

include karax/prelude


import threadlist, karaxutils

type
  State = ref object

proc newState(): State =
  State()

proc genHeader(): VNode =
  result = buildHtml(header(id="main-navbar")):
    tdiv(class="navbar container grid-xl"):
      section(class="navbar-section"):
        a(href="/"):
          img(src="images/crown.png", id="img-logo") # TODO: Customisation.
      section(class="navbar-section"):
        tdiv(class="input-group input-inline"):
          input(class="form-input input-sm", `type`="text", placeholder="search")
        button(class="btn btn-primary btn-sm"):
          italic(class="fas fa-user-plus")
          text " Sign up"
        button(class="btn btn-primary btn-sm"):
          italic(class="fas fa-sign-in-alt")
          text " Log in"

var state = newState()

proc render(): VNode =
  result = buildHtml(tdiv()):
    genHeader()
    renderThreadList()

setRenderer render