import options, httpcore, json, sugar, times, strformat, strutils

import threadlist, post, category, error, user

when defined(js):
  include karax/prelude
  import karax/[kajax, kdom]
  import karaxutils, postbutton, delete, profilesettings

  type
    ProfileTab* = enum
      Overview, Settings

    ProfileState* = ref object
      profile: Option[Profile]
      settings: Option[ProfileSettings]
      currentTab: ProfileTab
      loading: bool
      status: HttpCode

  proc newProfileState*(): ProfileState =
    ProfileState(
      loading: false,
      status: Http200,
      currentTab: Overview
    )

  proc onProfile(httpStatus: int, response: kstring, state: ProfileState) =
    # TODO: Try to abstract these.
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let profile = to(parsed, Profile)

    state.profile = some(profile)
    if profile.email.isSome():
      state.settings = some(newProfileSettings(profile))

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

  proc render*(
    state: ProfileState,
    username: string,
    currentUser: Option[User]
  ): VNode =
    if state.profile.isSome() and state.profile.get().user.name != username:
      state.profile = none[Profile]()
      state.status = Http200

    if state.status != Http200:
      return renderError("Couldn't retrieve profile.", state.status)

    if state.profile.isNone:
      let uri = makeUri("profile.json", ("username", username))
      ajaxGet(uri, @[], (s: int, r: kstring) => onProfile(s, r, state))

      return buildHtml(tdiv(class="loading loading-lg"))

    let profile = state.profile.get()
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
          if state.settings.isSome():
            render(state.settings.get(), currentUser)