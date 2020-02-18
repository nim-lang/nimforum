import options, json, httpcore

import category

when defined(js):
  include karax/prelude
  import karax / [vstyles, kajax]

  import karaxutils, error, user, mainbuttons

  type
    State = ref object
      list: Option[CategoryList]
      loading: bool
      status: HttpCode

  proc newState(): State =
    State(
      list: none[CategoryList](),
      loading: false,
      status: Http200
    )
  var
    state = newState()

  proc genCategory(category: Category, noBorder = false): VNode =
    result = buildHtml():
      tr(class=class({"no-border": noBorder})):
        td(style=style((StyleAttr.borderLeftColor, kstring("#" & category.color))), class="category"):
          h4(class="category-title"):
            a(href=makeUri("/c/" & $category.id), id="category-" & category.name.slug):
              tdiv():
                tdiv(class="category-name"):
                  text category.name
          tdiv(class="category-description"):
            text category.description
        td(class="topics"):
          text $category.numTopics

  proc onCategoriesRetrieved(httpStatus: int, response: kstring) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let list = to(parsed, CategoryList)

    if state.list.isSome:
      state.list.get().categories.add(list.categories)
    else:
      state.list = some(list)

  proc renderCategories(): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve threads.", state.status)

    if state.list.isNone:
      if not state.loading:
        state.loading = true
        ajaxGet(makeUri("categories.json"), @[], onCategoriesRetrieved)

      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get()

    return buildHtml():
      section(class="category-list"):
        table(id="categories-list", class="table"):
          thead():
            tr:
              th(text "Category")
              th(text "Topics")
          tbody():
            for i in 0 ..< list.categories.len:
              let category = list.categories[i]

              let isLastCategory = i+1 == list.categories.len
              genCategory(category, noBorder=isLastCategory)

  proc renderCategoryList*(currentUser: Option[User]): VNode =
    result = buildHtml(tdiv):
      renderMainButtons(currentUser)
      renderCategories()
