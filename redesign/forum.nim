include karax/prelude


proc genHeader(): VNode =
  result = buildHtml(header(id="main-navbar")):
    tdiv(class="navbar container grid-xl"):
      section(class="navbar-section"):
        a(href="/"):
          img(src="images/crown.png", id="img-logo") # TODO: Customisation.
      section(class="navbar-section"):
        tdiv(class="input-group input-inline"):
          input(class="form-input input-sm", `type`="text", placeholder="search")
        button(class="btn btn-primary btn-sm"):
          italic(class="fas fa-user-plus")
          text " Sign up"
        button(class="btn btn-primary btn-sm"):
          italic(class="fas fa-sign-in-alt")
          text " Log in"

proc genTopButtons(): VNode =
  result = buildHtml():
    section(class="navbar container grid-xl", id="main-buttons"):
      section(class="navbar-section"):
        tdiv(class="dropdown"):
          a(href="#", class="btn dropdown-toggle"):
            text "Filter "
            italic(class="fas fa-caret-down")
          ul(class="menu"):
            li: text "community"
            li: text "dev"
        button(class="btn btn-primary"): text "Latest"
        button(class="btn btn-link"): text "Most Active"
        button(class="btn btn-link"): text "Categories"
      section(class="navbar-section")


proc createDom(): VNode =
  result = buildHtml(tdiv()):
    genHeader()
    genTopButtons()

setRenderer createDom