import options
import user

when defined(js):
  include karax/prelude
  import karax / [kdom]

  import karaxutils, user, categorypicker, category

  let buttons = [
    (name: "Latest", url: makeUri("/"), id: "latest-btn"),
    (name: "Categories", url: makeUri("/categories"), id: "categories-btn"),
  ]

  proc onSelectedCategoryChanged(oldCategory: Category, newCategory: Category) =
    let uri = makeUri("/c/" & $newCategory.id)
    navigateTo(uri)

  type
    MainButtons* = ref object
      categoryPicker: CategoryPicker
      onCategoryChange*: CategoryChangeEvent

  proc newMainButtons*(onCategoryChange: CategoryChangeEvent = onSelectedCategoryChanged): MainButtons =
    new result
    result.onCategoryChange = onCategoryChange
    result.categoryPicker = newCategoryPicker(
      onCategoryChange = proc (oldCategory, newCategory: Category) =
        onSelectedCategoryChanged(oldCategory, newCategory)
        result.onCategoryChange(oldCategory, newCategory)
    )

  proc render*(state: MainButtons, currentUser: Option[User], categoryId = none(int)): VNode =
    result = buildHtml():
      section(class="navbar container grid-xl", id="main-buttons"):
        section(class="navbar-section"):
          #[tdiv(class="dropdown"):
            a(href="#", class="btn dropdown-toggle"):
              text "Filter "
              italic(class="fas fa-caret-down")
            ul(class="menu"):
              li: text "community"
              li: text "dev" ]#
          if categoryId.isSome:
            state.categoryPicker.selectedCategoryID = categoryId.get()
            render(state.categoryPicker, currentUser, compact=false)

          for btn in buttons:
            let active = btn.url == window.location.href
            a(id=btn.id, href=btn.url):
              button(class=class({"btn-primary": active, "btn-link": not active}, "btn")):
                text btn.name
        section(class="navbar-section"):
          if currentUser.isSome():
            a(id="new-thread-btn", href=makeUri("/newthread"), onClick=anchorCB):
              button(class="btn btn-secondary"):
                italic(class="fas fa-plus")
                text " New Thread"
