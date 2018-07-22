when defined(js):
  import httpcore, options, sugar, json, strutils, strformat

  include karax/prelude
  import karax/[kajax, kdom]

  import replybox, post, karaxutils, postbutton, error, delete, user

  type
    ProfileSettings* = ref object
      loading: bool
      status: HttpCode
      error: Option[PostError]
      email: kstring
      rank: Rank
      deleteModal: DeleteModal
      resetPassword: PostButton
      profile: Profile

  proc onUserDelete(user: User) =
    window.location.href = makeUri("/")

  proc resetSettings(state: ProfileSettings) =
    let profile = state.profile
    if profile.email.isSome():
      state.email = profile.email.get()
    else:
      state.email = ""
    state.rank = profile.user.rank

    state.error = none[PostError]()

  proc newProfileSettings*(profile: Profile): ProfileSettings =
    result = ProfileSettings(
      status: Http200,
      deleteModal: newDeleteModal(nil, nil, onUserDelete),
      resetPassword: newResetPasswordButton(profile.user.name),
      profile: profile
    )
    resetSettings(result)

  proc onProfilePost(httpStatus: int, response: kstring,
                     state: ProfileSettings) =
    postFinished:
     state.profile.email = some($state.email)
     state.profile.user.rank = state.rank

  proc onEmailChange(event: Event, node: VNode, state: ProfileSettings) =
    state.email = node.value

    if state.profile.user.rank != Admin:
      if state.email != state.profile.email.get():
        state.rank = EmailUnconfirmed
      else:
        state.rank = state.profile.user.rank

  proc onRankChange(event: Event, node: VNode, state: ProfileSettings) =
    state.rank = parseEnum[Rank]($node.value)

  proc save(state: ProfileSettings) =
    if state.loading:
      return
    state.loading = true
    state.error = none[PostError]()

    let formData = newFormData()
    formData.append("email", state.email)
    formData.append("rank", $state.rank)
    formData.append("username", $state.profile.user.name)
    let uri = makeUri("/saveProfile")
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) => onProfilePost(s, r, state))

  proc needsSave(state: ProfileSettings): bool =
    if state.profile.email.isSome():
      result = state.email != state.profile.email.get()
    result = result or state.rank != state.profile.user.rank

  proc render*(state: ProfileSettings,
               currentUser: Option[User]): VNode =
    let canEditRank = currentUser.isSome() and
                      currentUser.get().rank > state.profile.user.rank
    let canResetPassword = state.profile.user.rank > EmailUnconfirmed

    let rankSelect = buildHtml(tdiv()):
      if canEditRank:
        select(id="rank-field",
               class="form-select", value = $state.rank,
               onchange=(e: Event, n: VNode) => onRankChange(e, n, state)):
          for r in Rank:
            option(text $r, id="rank-" & toLowerAscii($r))
        p(class="form-input-hint text-warning"):
          text "You can modify anyone's rank. Remember: with " &
               "great power comes great responsibility."
      else:
        input(id="rank-field", class="form-input",
              `type`="text", disabled="", value = $state.rank)
        p(class="form-input-hint"):
          text "Your rank determines the actions you can perform " &
               "on the forum."
        case state.rank:
        of Spammer, Troll:
          p(class="form-input-hint text-warning"):
            text "Your account was banned."
        of EmailUnconfirmed:
          p(class="form-input-hint text-warning"):
            text "You cannot post until you confirm your email."
        of Moderated:
          p(class="form-input-hint text-warning"):
            text "Your account is under moderation. This is a spam prevention "&
                 "measure. You can write posts but only moderators and admins "&
                 "will see them until your account is verified by them."
        else:
          discard

    result = buildHtml():
      tdiv(class="columns"):
        tdiv(class="column col-6"):
          form(class="form-horizontal"):
            tdiv(class="form-group"):
              tdiv(class="col-3 col-sm-12"):
                label(class="form-label"):
                  text "Username"
              tdiv(class="col-9 col-sm-12"):
                input(class="form-input",
                      `type`="text",
                      value=state.profile.user.name,
                      disabled="")
                p(class="form-input-hint"):
                  text fmt("Users can refer to you by writing" &
                           " @{state.profile.user.name} in their posts.")
            if state.profile.email.isSome():
              tdiv(class="form-group"):
                tdiv(class="col-3 col-sm-12"):
                  label(class="form-label"):
                    text "Email"
                tdiv(class="col-9 col-sm-12"):
                  input(id="email-input", class="form-input",
                        `type`="text", value=state.email,
                        oninput=(e: Event, n: VNode) =>
                          onEmailChange(e, n, state)
                       )
                  p(class="form-input-hint"):
                    text "Your avatar is linked to this email and can be " &
                         "changed at "
                    a(href="https://gravatar.com/emails"):
                      text "gravatar.com"
                    text ". Note that any changes to your email will " &
                         "require email verification."
            tdiv(class="form-group"):
              tdiv(class="col-3 col-sm-12"):
                label(class="form-label"):
                  text "Rank"
              tdiv(class="col-9 col-sm-12"):
                rankSelect
            tdiv(class="form-group"):
              tdiv(class="col-3 col-sm-12"):
                label(class="form-label"):
                  text "Password"
              tdiv(class="col-9 col-sm-12"):
                render(state.resetPassword,
                       disabled=not canResetPassword)
            tdiv(class="form-group"):
              tdiv(class="col-3 col-sm-12"):
                label(class="form-label"):
                  text "Account"
              tdiv(class="col-9 col-sm-12"):
                button(id="delete-account-btn",
                       class="btn btn-secondary", `type`="button",
                       onClick=(e: Event, n: VNode) =>
                       (state.deleteModal.show(state.profile.user))):
                  italic(class="fas fa-times")
                  text " Delete account"

          tdiv(class="float-right"):
            if state.error.isSome():
              span(class="text-error"):
                text state.error.get().message

            button(id="cancel-btn",
                   class=class(
                    {"disabled": not needsSave(state)}, "btn btn-link"
                   ),
                   onClick=(e: Event, n: VNode) => (resetSettings(state))):
              text "Cancel"

            button(id="save-btn",
                   class=class(
                    {"disabled": not needsSave(state)}, "btn btn-primary"
                   ),
                   onClick=(e: Event, n: VNode) => save(state),
                   id="save-btn"):
              italic(class="fas fa-save")
              text " Save"

        render(state.deleteModal)

    # TODO: I really should just be able to set the `value` attr.
    # TODO: This doesn't work when settings are reset for some reason.
    let rankField = getVNodeById("rank-field")
    if not rankField.isNil:
      rankField.setInputText($state.rank)
    let emailField = getVNodeById("email-field")
    if not emailField.isNil:
      emailField.setInputText($state.email)
