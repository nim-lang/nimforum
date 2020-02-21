import options, json, httpcore

import category

when defined(js):
  import sugar
  include karax/prelude
  import karax / [vstyles, kajax]

  import karaxutils, error, user, mainbuttons, addcategorymodal

  type
    State = ref object
      list: Option[CategoryList]
      loading: bool
      status: HttpCode
      addCategoryModal: AddCategoryModal

  var state: State

  proc newState(): State =
    State(
      list: none[CategoryList](),
      loading: false,
      status: Http200,
      addCategoryModal: newAddCategoryModal(
        onAddCategory=
          (category: Category) => state.list.get().categories.add(category)
      )
    )

  state = newState()

  proc genCategory(category: Category, noBorder = false): VNode =
    result = buildHtml():
      tr(class=class({"no-border": noBorder})):
        td(style=style((StyleAttr.borderLeftColor, kstring("#" & category.color))), class="category"):
          h4(class="category-title", id="category-" & category.name.slug):
            a(href=makeUri("/c/" & $category.id)):
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

  proc renderCategoryHeader*(currentUser: Option[User]): VNode =
    result = buildHtml(tdiv(id="add-category")):
      text "Category"
      if currentUser.isAdmin():
        button(class="plus-btn btn btn-link",
              onClick=(ev: Event, n: VNode) => (
                state.addCategoryModal.setModalShown(true)
              )):
          italic(class="fas fa-plus")
        render(state.addCategoryModal)

  proc renderCategories(currentUser: Option[User]): VNode =
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
              th:
                renderCategoryHeader(currentUser)
              th(text "Topics")
          tbody():
            for i in 0 ..< list.categories.len:
              let category = list.categories[i]

              let isLastCategory = i+1 == list.categories.len
              genCategory(category, noBorder=isLastCategory)

  proc renderCategoryList*(currentUser: Option[User]): VNode =
    result = buildHtml(tdiv):
      renderMainButtons(currentUser)
      renderCategories(currentUser)
