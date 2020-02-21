when defined(js):
  import sugar, httpcore, options, json, strutils, algorithm
  import dom except Event

  include karax/prelude
  import karax / [kajax, kdom, vdom]

  import error, category, user
  import category, karaxutils, addcategorymodal

  type
    CategoryPicker* = ref object of VComponent
      list: Option[CategoryList]
      selectedCategoryID*: int
      loading: bool
      addEnabled: bool
      status: HttpCode
      error: Option[PostError]
      addCategoryModal: AddCategoryModal
      onCategoryChange: CategoryChangeEvent
      onAddCategory: CategoryEvent

  proc onCategoryLoad(state: CategoryPicker): proc (httpStatus: int, response: kstring) =
    return
      proc (httpStatus: int, response: kstring) =
        state.loading = false
        state.status = httpStatus.HttpCode
        if state.status != Http200: return

        let parsed = parseJson($response)
        let list = parsed.to(CategoryList)
        list.categories.sort(cmpNames)

        if state.list.isSome:
          state.list.get().categories.add(list.categories)
        else:
          state.list = some(list)

        if state.selectedCategoryID > state.list.get().categories.len():
          state.selectedCategoryID = 0

  proc loadCategories(state: CategoryPicker) =
    if not state.loading:
      state.loading = true
      ajaxGet(makeUri("categories.json"), @[], onCategoryLoad(state))

  proc `[]`*(state: CategoryPicker, id: int): Category =
    for cat in state.list.get().categories:
      if cat.id == id:
        return cat
    raise newException(IndexError, "Category at " & $id & " not found!")

  let nullAddCategory: CategoryEvent = proc (category: Category) = discard
  let nullCategoryChange: CategoryChangeEvent = proc (oldCategory: Category, newCategory: Category) = discard

  proc select*(state: CategoryPicker, id: int) =
    state.selectedCategoryID = id
    state.markDirty()

  proc onCategory(state: CategoryPicker): CategoryEvent =
    result =
      proc (category: Category) =
        state.list.get().categories.add(category)
        state.list.get().categories.sort(cmpNames)
        state.select(category.id)
        state.onAddCategory(category)

  proc newCategoryPicker*(onCategoryChange=nullCategoryChange, onAddCategory=nullAddCategory): CategoryPicker =
    result = CategoryPicker(
      list: none[CategoryList](),
      selectedCategoryID: 0,
      loading: false,
      addEnabled: false,
      status: Http200,
      error: none[PostError](),
      onCategoryChange: onCategoryChange,
      onAddCategory: onAddCategory
    )

    let state = result
    result.addCategoryModal = newAddCategoryModal(
      onAddCategory=onCategory(state)
    )

  proc setAddEnabled*(state: CategoryPicker, enabled: bool) =
    state.addEnabled = enabled

  proc onCategoryClick(state: CategoryPicker, category: Category): proc (ev: Event, n: VNode) =
    # this is necessary to capture the right value
    let cat = category
    return
      proc (ev: Event, n: VNode) =
        let oldCategory = state[state.selectedCategoryID]
        state.select(cat.id)
        state.onCategoryChange(oldCategory, cat)

  proc genAddCategory(state: CategoryPicker): VNode =
    result = buildHtml():
      tdiv(id="add-category"):
        button(class="plus-btn btn btn-link",
               onClick=(ev: Event, n: VNode) => (
                 state.addCategoryModal.setModalShown(true)
               )):
          italic(class="fas fa-plus")
        render(state.addCategoryModal)

  proc render*(state: CategoryPicker, currentUser: Option[User], compact=true): VNode =
    if currentUser.isAdmin():
      state.setAddEnabled(true)

    if state.status != Http200:
      return renderError("Couldn't retrieve categories.", state.status)

    if state.list.isNone:
      state.loadCategories()
      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get().categories
    let selectedCategory = state[state.selectedCategoryID]

    result = buildHtml():
      tdiv(id="category-selection", class="input-group"):
        tdiv(class="dropdown"):
          a(class="btn btn-link dropdown-toggle", tabindex="0"):
            tdiv(class="selected-category d-inline-block"):
              render(selectedCategory)
            text " "
            italic(class="fas fa-caret-down")
          ul(class="menu"):
            for category in list:
              li(class="menu-item"):
                a(class="category-" & $category.id & " " & category.name.slug,
                  onClick=onCategoryClick(state, category)):
                  render(category, compact)
        if state.addEnabled:
          genAddCategory(state)
