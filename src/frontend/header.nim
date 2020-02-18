import options, httpcore

import user
type
  UserStatus* = object
    user*: Option[User]
    recaptchaSiteKey*: Option[string]

when defined(js):
  import times, json, sugar
  include karax/prelude
  import karax / [kajax, kdom]

  import login, signup, usermenu
  import karaxutils

  from dom import
    setTimeout, window, document, getElementById, focus


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
    if diff.inMinutes < 5:
      return

    state.loading = true
    let uri = makeUri("status.json", [("logout", $logout)])
    ajaxGet(uri, @[], onStatus)

  proc getLoggedInUser*(): Option[User] =
    state.data.map(x => x.user).flatten

  proc isLoggedIn*(): bool =
    not getLoggedInUser().isNone

  proc onKeyDown(e: Event, n: VNode) =
    let event = cast[KeyboardEvent](e)
    if event.key == "Enter":
      navigateTo(makeUri("/search", ("q", $n.value), reuseSearch=false))

  proc renderHeader*(): VNode =
    if state.data.isNone and state.status == Http200:
      getStatus()

    let user = state.data.map(x => x.user).flatten
    result = buildHtml(tdiv()):
      header(id="main-navbar"):
        tdiv(class="navbar container grid-xl"):
          section(class="navbar-section"):
            a(href=makeUri("/")):
              img(src="/images/logo.png", id="img-logo")
          section(class="navbar-section"):
            tdiv(class="input-group input-inline"):
              input(class="search-input input-sm",
                    `type`="text", placeholder="search",
                    id="search-box",
                    onKeyDown=onKeyDown)
            if state.loading:
              tdiv(class="loading")
            elif user.isNone:
              button(id="signup-btn", class="btn btn-primary btn-sm",
                     onClick=(e: Event, n: VNode) => state.signupModal.show()):
                italic(class="fas fa-user-plus")
                text " Sign up"
              button(id="login-btn", class="btn btn-primary btn-sm",
                     onClick=(e: Event, n: VNode) => state.loginModal.show()):
                italic(class="fas fa-sign-in-alt")
                text " Log in"
            else:
              render(state.userMenu, user.get())

      # Modals
      if state.data.isSome():
        render(state.loginModal, state.data.get().recaptchaSiteKey)
        render(state.signupModal, state.data.get().recaptchaSiteKey)