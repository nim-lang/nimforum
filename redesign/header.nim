import options, times, httpcore, json, sugar

import threadlist
type
  UserStatus* = object
    user*: Option[User]

when defined(js):
  include karax/prelude
  import karax / [kajax]

  import login
  import karaxutils

  from dom import setTimeout, window, document, getElementById, focus

  type
    State = ref object
      data: Option[UserStatus]
      loading: bool
      status: HttpCode
      lastUpdate: Time
      loginModal: LoginModal

  proc newState(): State
  var
    state = newState()

  proc getStatus
  proc newState(): State =
    State(
      data: none[UserStatus](),
      loading: false,
      status: Http200,
      loginModal: newLoginModal(
        () => (state.lastUpdate = fromUnix(0); getStatus())
      )
    )

  proc onStatus(httpStatus: int, response: kstring) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    state.data = some(to(parsed, UserStatus))

    state.lastUpdate = getTime()

  proc getStatus =
    if state.loading: return
    let diff = getTime() - state.lastUpdate
    if diff.minutes < 5:
      return

    state.loading = true
    let uri = makeUri("status.json")
    ajaxGet(uri, @[], onStatus)

  proc genSignUpModal(): VNode =
    result = buildHtml():
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
                  input(class="form-input", `type`="text", name="email")
                tdiv(class="form-group"):
                  label(class="form-label", `for`="regusername"):
                    text "Username"
                  input(class="form-input", `type`="text", name="username")
                tdiv(class="form-group"):
                  label(class="form-label", `for`="regpassword"):
                    text "Password"
                  input(class="form-input", `type`="password", name="password")
          tdiv(class="modal-footer"):
            button(class="btn btn-primary"):
              text "Create account"
            a(href="#login-modal"):
              button(class="btn"):
                text "Log in"

  proc renderHeader*(): VNode =
    if state.data.isNone:
      getStatus()

    let user = state.data.map(x => x.user).flatten
    result = buildHtml(tdiv()): # TODO: Why do some buildHtml's need this?
      header(id="main-navbar"):
        tdiv(class="navbar container grid-xl"):
          section(class="navbar-section"):
            a(href=makeUri("/")):
              img(src="images/crown.png", id="img-logo") # TODO: Customisation.
          section(class="navbar-section"):
            tdiv(class="input-group input-inline"):
              input(class="search-input input-sm",
                    `type`="text", placeholder="search",
                    id="search-box")
            if state.loading:
              tdiv(class="loading")
            elif user.isNone:
              a(href="#signup-modal", id="signup-btn"):
                button(class="btn btn-primary btn-sm"):
                  italic(class="fas fa-user-plus")
                  text " Sign up"
              button(class="btn btn-primary btn-sm",
                     onClick=(e: Event, n: VNode) => state.loginModal.show()):
                italic(class="fas fa-sign-in-alt")
                text " Log in"
            else:
              render(user.get(), "avatar")

      # Modals
      render(state.loginModal)

      genSignUpModal()