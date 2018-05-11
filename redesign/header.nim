import options, times, httpcore, json, sugar

import threadlist
type
  UserStatus* = object
    user*: Option[User]

when defined(js):
  include karax/prelude
  import karax / [kajax]


  import karaxutils

  from dom import setTimeout, window, document, getElementById

  type
    State = ref object
      data: Option[UserStatus]
      loading: bool
      status: HttpCode
      lastUpdate: Time

  proc newState(): State =
    State(
      data: none[UserStatus](),
      loading: false,
      status: Http200
    )

  var
    state = newState()

  proc getStatus
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

  proc onLogInPost(httpStatus: int, response: kstring) =
    kout(response)

  proc onLogInClick(ev: Event, n: VNode) =
    let uri = makeUri("login")
    let form = document.getElementById("login-form")
    # TODO: This is a hack, karax should support this.
    let formData = newFormData(form)
    kout(formData.get("username"))
    ajaxPost(uri, @[], cast[cstring](formData), onLogInPost)

  proc genLoginModal(): VNode =
    result = buildHtml():
      tdiv(class="modal modal-sm", id="login-modal"):
        a(href="#", class="modal-overlay", "aria-label"="close")
        tdiv(class="modal-container"):
          tdiv(class="modal-header"):
            a(href="#", class="btn btn-clear float-right", "aria-label"="close")
            tdiv(class="modal-title h5"):
              text "Log in"
          tdiv(class="modal-body"):
            tdiv(class="content"):
              form(id="login-form"):
                tdiv(class="form-group"):
                  label(class="form-label", `for`="username"):
                    text "Username"
                  input(class="form-input", `type`="text", name="username")
                tdiv(class="form-group"):
                  label(class="form-label", `for`="password"):
                    text "Password"
                  input(class="form-input", `type`="password", name="password")
              a(href="#reset-password-modal"):
                text "Reset your password"
          tdiv(class="modal-footer"):
            button(class="btn btn-primary", onClick=onLogInClick):
              text "Log in"
            a(href="#signup-modal"):
              button(class="btn"):
                text "Create account"

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
              input(class="search-input input-sm", `type`="text", placeholder="search")
            if state.loading:
              tdiv(class="loading")
            elif user.isNone:
              a(href="#signup-modal", id="signup-btn"):
                button(class="btn btn-primary btn-sm"):
                  italic(class="fas fa-user-plus")
                  text " Sign up"
              a(href="#login-modal", id="login-btn"):
                button(class="btn btn-primary btn-sm"):
                  italic(class="fas fa-sign-in-alt")
                  text " Log in"
            else:
              render(user.get(), "avatar")

      # Modals
      genLoginModal()

      genSignUpModal()