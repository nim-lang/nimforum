import options, times, httpcore, json, sugar

import threadlist
type
  UserStatus* = object
    user*: Option[User]

when defined(js):
  include karax/prelude
  import karax / [kajax]

  import login, signup, usermenu
  import karaxutils

  from dom import setTimeout, window, document, getElementById, focus

  type
    State = ref object
      data: Option[UserStatus]
      loading: bool
      status: HttpCode
      lastUpdate: Time
      loginModal: LoginModal
      signupModal: SignupModal
      userMenu: UserMenu

  proc newState(): State
  var
    state = newState()

  proc getStatus(logout: bool=false)
  proc newState(): State =
    State(
      data: none[UserStatus](),
      loading: false,
      status: Http200,
      loginModal: newLoginModal(
        () => (state.lastUpdate = fromUnix(0); getStatus()),
        () => state.signupModal.show()
      ),
      signupModal: newSignupModal(
        () => (state.lastUpdate = fromUnix(0); getStatus()),
        () => state.loginModal.show()
      ),
      userMenu: newUserMenu(
        () => (state.lastUpdate = fromUnix(0); getStatus(logout=true))
      )
    )

  proc onStatus(httpStatus: int, response: kstring) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    state.data = some(to(parsed, UserStatus))

    state.lastUpdate = getTime()

  proc getStatus(logout: bool=false) =
    if state.loading: return
    let diff = getTime() - state.lastUpdate
    if diff.minutes < 5:
      return

    state.loading = true
    let uri = makeUri("status.json", [("logout", $logout)])
    ajaxGet(uri, @[], onStatus)

  proc isLoggedIn*(): bool =
    let user = state.data.map(x => x.user).flatten
    not user.isNone

  proc renderHeader*(): VNode =
    if state.data.isNone:
      getStatus() # TODO: Call this every render?

    let user = state.data.map(x => x.user).flatten
    result = buildHtml(tdiv()): # TODO: Why do some buildHtml's need this?
      header(id="main-navbar"):
        tdiv(class="navbar container grid-xl"):
          section(class="navbar-section"):
            a(href=makeUri("/")):
              img(src="/karax/images/crown.png", id="img-logo") # TODO: Customisation.
          section(class="navbar-section"):
            tdiv(class="input-group input-inline"):
              input(class="search-input input-sm",
                    `type`="text", placeholder="search",
                    id="search-box")
            if state.loading:
              tdiv(class="loading")
            elif user.isNone:
              button(class="btn btn-primary btn-sm",
                     onClick=(e: Event, n: VNode) => state.signupModal.show()):
                italic(class="fas fa-user-plus")
                text " Sign up"
              button(class="btn btn-primary btn-sm",
                     onClick=(e: Event, n: VNode) => state.loginModal.show()):
                italic(class="fas fa-sign-in-alt")
                text " Log in"
            else:
              render(state.userMenu, user.get())

      # Modals
      render(state.loginModal)

      render(state.signupModal)