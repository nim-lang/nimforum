when defined(js):
  import sugar, httpcore, options, json
  import dom except Event, KeyboardEvent
  import jsffi except `&`

  include karax/prelude
  import karax / [kajax, kdom]

  import error, replybox, threadlist, post
  import karaxutils

  type
    ResetPassword* = ref object
      loading: bool
      status: HttpCode
      error: Option[PostError]
      newPassword: kstring

  proc newResetPassword*(): ResetPassword =
    ResetPassword(
      status: Http200,
      newPassword: ""
    )

  proc onPassChange(e: Event, n: VNode, state: ResetPassword) =
    state.newPassword = n.value

  proc onPost(httpStatus: int, response: kstring, state: ResetPassword) =
    postFinished:
      navigateTo(makeUri("/resetPassword/success"))

  proc onSetClick(
    ev: Event, n: VNode,
    state: ResetPassword
  ) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("resetPassword", ("newPassword", $state.newPassword))
    ajaxPost(uri, @[], "",
             (s: int, r: kstring) => onPost(s, r, state))

  proc render*(state: ResetPassword): VNode =
    if state.loading:
      return buildHtml(tdiv(class="loading"))

    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(id="resetpassword"):
          tdiv(class="title"):
            p(): text "Reset Password"
          tdiv(class="content"):
            label(class="form-label", `for`="password"):
              text "Password"
            input(class="form-input", `type`="password", name="password",
                  placeholder="Type your new password here",
                  oninput=(e: Event, n: VNode) => onPassChange(e, n, state))
            if state.error.isSome():
              p(class="text-error"):
                text state.error.get().message
          tdiv(class="footer"):
            button(class=class(
                    {"loading": state.loading},
                    "btn btn-primary"
                   ),
                   onClick=(ev: Event, n: VNode) =>
                    (onSetClick(ev, n, state))):
              text "Set password"


  type
    ResetPasswordModal* = ref object
      shown: bool
      loading: bool
      error: Option[PostError]
      sent: bool

  proc onPost(httpStatus: int, response: kstring, state: ResetPasswordModal) =
    postFinished:
      state.sent = true

  proc onClick(ev: Event, n: VNode, state: ResetPasswordModal) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("sendResetPassword")
    let form = dom.document.getElementById("resetpassword-form")
    # TODO: This is a hack, karax should support this.
    let formData = newFormData(form)
    ajaxPost(uri, @[], formData.to(cstring),
             (s: int, r: kstring) => onPost(s, r, state))

    ev.preventDefault()

  proc onClose(ev: Event, n: VNode, state: ResetPasswordModal) =
    state.shown = false
    ev.preventDefault()

  proc newResetPasswordModal*(): ResetPasswordModal =
    ResetPasswordModal(
      shown: false
    )

  proc show*(state: ResetPasswordModal) =
    state.shown = true

  proc onKeyDown(e: Event, n: VNode, state: ResetPasswordModal) =
    let event = cast[KeyboardEvent](e)
    if event.key == "Enter":
      onClick(e, n, state)

  proc render*(state: ResetPasswordModal,
               recaptchaSiteKey: Option[string]): VNode =
    result = buildHtml():
      tdiv(class=class({"active": state.shown}, "modal"),
           id="resetpassword-modal"):
        a(href="", class="modal-overlay", "aria-label"="close",
          onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
        tdiv(class="modal-container"):
          tdiv(class="modal-header"):
            a(href="", class="btn btn-clear float-right",
              "aria-label"="close",
              onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
            tdiv(class="modal-title h5"):
              text "Reset your password"
          tdiv(class="modal-body"):
            tdiv(class="content"):
              form(id="resetpassword-form",
                   onKeyDown=(ev: Event, n: VNode) => onKeyDown(ev, n, state)):
                genFormField(
                  state.error,
                  "email",
                  "Enter your email or username and we will send you a " &
                  "password reset email.",
                  "text",
                  true,
                  placeholder="Username or email"
                )
                if recaptchaSiteKey.isSome:
                  tdiv(id="recaptcha"):
                    tdiv(class="g-recaptcha",
                         "data-sitekey"=recaptchaSiteKey.get())
                    script(src="https://www.google.com/recaptcha/api.js")
          tdiv(class="modal-footer"):
            if state.sent:
              span(class="text-success"):
                italic(class="fas fa-check-circle")
                text " Sent"
            else:
              button(class=class(
                      {"loading": state.loading},
                      "btn btn-primary"
                     ),
                     `type`="button",
                     onClick=(ev: Event, n: VNode) => onClick(ev, n, state)):
                text "Reset password"
