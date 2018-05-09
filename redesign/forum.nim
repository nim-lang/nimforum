import strformat, times, options, json

include karax/prelude
import karax / [vstyles, kajax]

import threadlist, karaxutils

type
  State = ref object
    list: Option[ThreadList]

proc newState(): State =
  State(
    list: none[ThreadList]()
  )

const
  baseUrl = "http://localhost:5000/"

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

proc onThreadList(httpStatus: int, response: kstring) =
  let parsed = parseJson($response)
  let list = to(parsed, ThreadList)

  if state.list.isSome:
    state.list.get().threads.add(list.threads)
    state.list.get().moreCount = list.moreCount
    state.list.get().lastVisit = list.lastVisit
  else:
    state.list = some(list)

proc render(): VNode =
  if state.list.isNone:
    ajaxGet(baseUrl & "threads.json", @[], onThreadList)

  result = buildHtml(tdiv()):
    genHeader()
    genTopButtons()
    if state.list.isNone:
      tdiv(class="loading loading-lg")
    else:
      genThreadList(state.list.get())

setRenderer render