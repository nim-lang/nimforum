
when defined(js):
  import sugar

  include karax/prelude
  import karax/[vstyles]
  import karaxutils

  import threadlist
  type
    UserMenu* = ref object
      shown: bool
      user: User
      onLogout: proc ()

  proc newUserMenu*(onLogout: proc ()): UserMenu =
    UserMenu(
      shown: false,
      onLogout: onLogout
    )

  proc render*(state: UserMenu, user: User): VNode =
    result = buildHtml():
      tdiv():
        figure(class="avatar c-hand",
               onClick=(e: Event, n: VNode) => (state.shown = true)):
          img(src=user.avatarUrl, title=user.name)
          if user.isOnline:
            italic(class="avatar-presense online")

        ul(class="menu menu-right", style=style(
          StyleAttr.display, if state.shown: "inherit" else: "none"
        )):
          li(class="menu-item"):
            tdiv(class="tile tile-centered"):
              tdiv(class="tile-icon"):
                img(class="avatar", src=user.avatarUrl,
                    title=user.name)
              tdiv(class="tile-content"):
                text user.name
          li(class="divider")
          li(class="menu-item"):
            a(href=makeUri("/profile/" & user.name)):
              text "My profile"
          li(class="menu-item c-hand"):
            a(onClick = (e: Event, n: VNode) =>
                (state.shown=false; state.onLogout())):
              text "Logout"