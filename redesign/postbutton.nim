## Simple generic button that can be clicked to make a post request.
## The button will show a loading indicator and a tick on success.
##
## Used for password reset emails.

import options, httpcore, json, sugar
when defined(js):
  include karax/prelude
  import karax/[kajax, kdom]

  import error, karaxutils

  type
    PostButton* = ref object
      uri, title, icon: string
      formData: FormData
      error: Option[PostError]
      loading: bool
      posted: bool

  proc newPostButton*(uri: string, formData: FormData,
                      title: string, icon: string): PostButton =
    PostButton(
      uri: uri,
      formData: formData,
      title: title,
      icon: icon
    )

  proc newResetPasswordButton*(email: string): PostButton =
    var formData = newFormData()
    formData.append("email", email)
    result = newPostButton(
        makeUri("/resetPassword"),
        formData,
        "Send password reset email",
        "fas fa-envelope",
    )

  proc onPost(httpStatus: int, response: kstring, state: PostButton) =
    postFinished:
      discard

  proc onClick(ev: Event, n: VNode, state: PostButton) =
    if state.loading or state.posted: return

    state.loading = true
    state.posted = true
    state.error = none[PostError]()

    # TODO: This is a hack, karax should support this.
    ajaxPost(state.uri, @[], cast[cstring](state.formData),
             (s: int, r: kstring) => onPost(s, r, state))

    ev.preventDefault()

  proc render*(state: PostButton, disabled: bool): VNode =
    result = buildHtml(tdiv()):
      button(class=class({
                "loading": state.loading,
                "disabled": disabled
              },
              "btn btn-secondary"
             ),
             onClick=(e: Event, n: VNode) => (onClick(e, n, state))):
        if state.posted:
          if state.error.isNone():
            italic(class="fas fa-check")
          else:
            italic(class="fas fa-times")
        else:
          italic(class=state.icon)
        text " " & state.title

      if state.error.isSome():
        p(class="text-error"):
          text state.error.get().message