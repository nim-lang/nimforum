when defined(js):
  import sugar, httpcore, options, json
  import dom except Event

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