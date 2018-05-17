import options, httpcore, json, sugar, times, strformat

import threadlist, post, category, error, user

type
  Profile* = object
    user*: User
    joinTime*: int64
    threads*: seq[PostLink]
    posts*: seq[PostLink]
    postCount*: int
    threadCount*: int
    # Information that only admins should see.
    email*: Option[string]

when defined(js):
  include karax/prelude
  import karax/[kajax]
  import karaxutils, postbutton

  type
    ProfileTab* = enum
      Overview, Settings

    ProfileSettings* = object
      email: kstring
      rank: Rank

    ProfileState* = ref object
      profile: Option[Profile]
      settings: ProfileSettings
      currentTab: ProfileTab
      loading: bool
      status: HttpCode
      resetPassword: Option[PostButton]

  proc newProfileState*(): ProfileState =
    ProfileState(
      loading: false,
      status: Http200,
      currentTab: Overview,
      settings: ProfileSettings(
        email: "",
        rank: Spammer
      )
    )

  proc resetSettings(state: ProfileState) =
    let profile = state.profile.get()
    if profile.email.isSome():
      state.settings = ProfileSettings(
        email: profile.email.get(),
        rank: profile.user.rank
      )

  proc onProfile(httpStatus: int, response: kstring, state: ProfileState) =
    # TODO: Try to abstract these.
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let profile = to(parsed, Profile)

    state.profile = some(profile)
    resetSettings(state)
    if profile.email.isSome():
      state.resetPassword = some(newResetPasswordButton(profile.email.get()))

  proc genPostLink(link: PostLink): VNode =
    let url = renderPostUrl(link)
    result = buildHtml():
      tdiv(class="profile-post"):
        tdiv(class="profile-post-main"):
          tdiv(class="profile-post-title"):
            a(href=url):
              text link.topic
            tdiv(class="profile-post-time"):
              let title = link.creation.fromUnix().local.
                          format("MMM d, yyyy HH:mm")
              p(title=title):
                text renderActivity(link.creation)

  proc onEmailChange(event: Event, node: VNode, state: ProfileState) =
    state.settings.email = node.value

    if state.settings.email != state.profile.get().email.get():
      state.settings.rank = EmailUnconfirmed
    else:
      state.settings.rank = state.profile.get().user.rank

  proc render*(
    state: ProfileState,
    username: string,
    currentUser: Option[User]
  ): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve profile.")

    if state.profile.isNone or state.profile.get().user.name != username:
      let uri = makeUri("profile.json", ("username", username))
      ajaxGet(uri, @[], (s: int, r: kstring) => onProfile(s, r, state))

      return buildHtml(tdiv(class="loading loading-lg"))

    let profile = state.profile.get()
    let isAdmin = currentUser.isSome() and currentUser.get().rank == Admin

    let rankSelect = buildHtml(tdiv()):
      if isAdmin:
        select(class="form-select", value = $state.settings.rank):
          for r in Rank:
            option(text $r)
        p(class="form-input-hint text-warning"):
          text "As an admin you can modify anyone's rank. Remember: with " &
               "great power comes great responsibility."
      else:
        input(class="form-input",
              `type`="text", value = $state.settings.rank, disabled="")
        p(class="form-input-hint"):
          text "Your rank determines the actions you can perform " &
               "on the forum."
        case state.settings.rank:
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
      section(class="container grid-xl"):
        tdiv(class="profile"):
          tdiv(class="profile-icon"):
            render(profile.user, "profile-avatar")
          tdiv(class="profile-content"):
            h2(class="profile-title"):
              text profile.user.name

        tdiv(class="profile-stats"):
          dl():
            dt(text "Joined")
            dd(text threadlist.renderActivity(profile.joinTime))
            if profile.posts.len > 0:
              dt(text "Last Post")
              dd(text renderActivity(profile.posts[0].creation))
            dt(text "Last Online")
            dd(text renderActivity(profile.user.lastOnline))
            dt(text "Posts")
            dd():
              if profile.postCount > 999:
                text $(profile.postCount / 1000) & "k"
              else:
                text $profile.postCount
            dt(text "Threads")
            dd():
              if profile.threadCount > 999:
                text $(profile.threadCount / 1000) & "k"
              else:
                text $profile.threadCount
            dt(text "Rank")
            dd(text $profile.user.rank)

        if currentUser.isSome():
          let user = currentUser.get()
          if user.name == profile.user.name or user.rank == Admin:
            ul(class="tab"):
              li(class=class(
                  {"active": state.currentTab == Overview},
                  "tab-item"
                 ),
                 onClick=(e: Event, n: VNode) => (state.currentTab = Overview)
                ):
                a(class="c-hand"):
                  text "Overview"
              li(class=class(
                  {"active": state.currentTab == Settings},
                  "tab-item"
                 ),
                 onClick=(e: Event, n: VNode) => (state.currentTab = Settings)
                ):
                a(class="c-hand"):
                  italic(class="fas fa-cog")
                  text " Settings"

        case state.currentTab
        of Overview:
          if profile.posts.len > 0 or profile.threads.len > 0:
            tdiv(class="columns"):
              tdiv(class="column col-6"):
                h4(text "Latest Posts")
                tdiv(class="posts"):
                  for post in profile.posts:
                    genPostLink(post)
              tdiv(class="column col-6"):
                h4(text "Latest Threads")
                tdiv(class="posts"):
                  for thread in profile.threads:
                    genPostLink(thread)
        of Settings:
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
                          value=profile.user.name,
                          disabled="")
                    p(class="form-input-hint"):
                      text fmt("Users can refer to you by writing" &
                               " @{profile.user.name} in their posts.")
                tdiv(class="form-group"):
                  tdiv(class="col-3 col-sm-12"):
                    label(class="form-label"):
                      text "Email"
                  tdiv(class="col-9 col-sm-12"):
                    input(class="form-input",
                          `type`="text", value=state.settings.email,
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
                if state.resetPassword.isSome():
                  tdiv(class="form-group"):
                    tdiv(class="col-3 col-sm-12"):
                      label(class="form-label"):
                        text "Password"
                    tdiv(class="col-9 col-sm-12"):
                      render(state.resetPassword.get(),
                             disabled=state.settings.rank==EmailUnconfirmed)

              tdiv(class="float-right"):
                button(class="btn btn-link",
                       onClick=(e: Event, n: VNode) => (resetSettings(state))):
                  text "Cancel"

                button(class="btn btn-primary"):
                  italic(class="fas fa-check")
                  text " Save"