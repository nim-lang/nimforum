when defined(js):
  import sugar, httpcore, options, json, strutils
  import dom except Event

  include karax/prelude
  import karax / [kajax, kdom, vstyles, vdom]

  import error, replybox, threadlist, post, category
  import category, karaxutils

  type
    CategoryPicker* = ref object of VComponent
      list: Option[CategoryList]
      selectedCategoryID*: int
      loading: bool
      status: HttpCode

  proc slug(name: string): string =
    name.strip().replace(" ", "-").toLowerAscii

  proc onCategoryList(state: CategoryPicker): proc (httpStatus: int, response: kstring) =
    return proc (httpStatus: int, response: kstring) =
      state.loading = false
      state.status = httpStatus.HttpCode
      if state.status != Http200: return

      let parsed = parseJson($response)
      let list = parsed.to(CategoryList)

      if state.list.isSome:
        state.list.get().categories.add(list.categories)
      else:
        state.list = some(list)

      if state.selectedCategoryID > state.list.get().categories.len():
        state.selectedCategoryID = 0

  proc loadCategories(state: CategoryPicker) =
    if not state.loading:
      state.loading = true
      ajaxGet(makeUri("categories.json"), @[], onCategoryList(state))

  proc newCategoryPicker*(): CategoryPicker =
    result = CategoryPicker(
      list: none[CategoryList](),
      selectedCategoryID: 0,
      loading: false,
      status: Http200
    )

  proc onCategoryClick(state: CategoryPicker, category: Category): proc (ev: Event, n: VNode) =
    # this is necessary to capture the right value
    let cat = category
    return proc (ev: Event, n: VNode) =
      state.selectedCategoryID = cat.id
      state.markDirty()

  proc render*(state: CategoryPicker): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve categories.", state.status)

    if state.list.isNone:
      state.loadCategories()
      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get().categories
    let selectedCategory = list[state.selectedCategoryID]

    result = buildHtml():
      tdiv(id="category-selection", class="input-group"):
        label(class="d-inline-block form-label"):
          text "Category"
        tdiv(class="dropdown"):
          a(class="btn btn-link dropdown-toggle", tabindex="0"):
            tdiv(class="d-inline-block"):
              render(selectedCategory)
            text " "
            italic(class="fas fa-caret-down")
          ul(class="menu"):
            for category in list:
              li(class="menu-item"):
                a(class="category-" & $category.id & " " & category.name.slug,
                  onClick=onCategoryClick(state, category)):
                  render(category)