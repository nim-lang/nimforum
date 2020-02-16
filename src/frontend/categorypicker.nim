when defined(js):
  import sugar, httpcore, options, json, strutils, algorithm
  import dom except Event
  import jsffi except `&`

  include karax/prelude
  import karax / [kajax, kdom, vstyles, vdom]

  import error, replybox, threadlist, post, category, user
  import category, karaxutils

  type
    CategoryPicker* = ref object of VComponent
      list: Option[CategoryList]
      selectedCategoryID*: int
      loading: bool
      modalShown: bool
      addEnabled: bool
      status: HttpCode
      error: Option[PostError]
      onCategoryChange: proc (oldCategory: Category, newCategory: Category)
      onAddCategory: proc (category: Category)

  proc slug(name: string): string =
    name.strip().replace(" ", "-").toLowerAscii

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

  proc nullAddCategory(category: Category) = discard
  proc nullCategoryChange(oldCategory: Category, newCategory: Category) = discard

  proc newCategoryPicker*(
      onCategoryChange: proc(oldCategory: Category, newCategory: Category) = nullCategoryChange,
      onAddCategory: proc(category: Category) = nullAddCategory
    ): CategoryPicker =
    result = CategoryPicker(
      list: none[CategoryList](),
      selectedCategoryID: 0,
      loading: false,
      modalShown: false,
      addEnabled: false,
      status: Http200,
      error: none[PostError](),
      onCategoryChange: onCategoryChange,
      onAddCategory: onAddCategory
    )

  proc setAddEnabled*(state: CategoryPicker, enabled: bool) =
    state.addEnabled = enabled

  proc select*(state: CategoryPicker, id: int) =
    state.selectedCategoryID = id
    state.markDirty()

  proc onCategoryClick(state: CategoryPicker, category: Category): proc (ev: Event, n: VNode) =
    # this is necessary to capture the right value
    let cat = category
    return
      proc (ev: Event, n: VNode) =
        let oldCategory = state[state.selectedCategoryID]
        state.select(cat.id)
        state.onCategoryChange(oldCategory, cat)

  proc onAddCategoryPost(httpStatus: int, response: kstring, state: CategoryPicker) =
    postFinished:
      state.modalShown = false
      let j = parseJson($response)
      let category = j.to(Category)

      state.list.get().categories.add(category)
      state.list.get().categories.sort(cmpNames)
      state.select(category.id)

      state.onAddCategory(category)

  proc onAddCategoryClick(state: CategoryPicker) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("createCategory")
    let form = dom.document.getElementById("add-category-form")
    let formData = newFormData(form)

    ajaxPost(uri, @[], formData.to(cstring),
             (s: int, r: kstring) => onAddCategoryPost(s, r, state))

  proc onClose(ev: Event, n: VNode, state: CategoryPicker) =
    state.modalShown = false
    state.markDirty()
    ev.preventDefault()

  proc genAddCategory(state: CategoryPicker): VNode =
    result = buildHtml():
      tdiv(id="add-category"):
        button(class="plus-btn btn btn-link",
               onClick=(ev: Event, n: VNode) => (
                 state.modalShown = true;
                 state.markDirty()
               )):
          italic(class="fas fa-plus")
        tdiv(class=class({"active": state.modalShown}, "modal modal-sm")):
          a(href="", class="modal-overlay", "aria-label"="close",
            onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
          tdiv(class="modal-container"):
            tdiv(class="modal-header"):
              tdiv(class="card-title h5"):
                text "Add New Category"
            tdiv(class="modal-body"):
              form(id="add-category-form"):
                genFormField(
                  state.error, "name", "Name", "text", false,
                  placeholder="Category Name")
                genFormField(
                  state.error, "color", "Color", "color", false,
                  placeholder="#XXYYZZ"
                )
                genFormField(
                  state.error,
                  "description",
                  "Description",
                  "text",
                  true,
                  placeholder="Description"
                )
            tdiv(class="modal-footer"):
              button(
                id="add-category-btn",
                class="btn btn-primary",
                onClick=(ev: Event, n: VNode) =>
                      state.onAddCategoryClick()):
                text "Add"

  proc render*(state: CategoryPicker, currentUser: Option[User]): VNode =
    let loggedIn = currentUser.isSome()
    let currentAdmin =
      loggedIn and currentUser.get().rank == Admin

    if currentAdmin:
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
                  render(category)
        if state.addEnabled:
          genAddCategory(state)
