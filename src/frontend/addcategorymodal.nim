when defined(js):
  import sugar, httpcore, options, json, strutils
  import dom except Event
  import jsffi except `&`

  include karax/prelude
  import karax / [kajax, kdom, vdom]

  import error, category
  import category, karaxutils

  type
    AddCategoryModal* = ref object of VComponent
      modalShown: bool
      loading: bool
      error: Option[PostError]
      onAddCategory: CategoryEvent

  let nullCategory: CategoryEvent = proc (category: Category) = discard

  proc newAddCategoryModal*(onAddCategory=nullCategory): AddCategoryModal =
    result = AddCategoryModal(
      modalShown: false,
      loading: false,
      onAddCategory: onAddCategory
    )

  proc onAddCategoryPost(httpStatus: int, response: kstring, state: AddCategoryModal) =
    postFinished:
      state.modalShown = false
      let j = parseJson($response)
      let category = j.to(Category)

      state.onAddCategory(category)

  proc onAddCategoryClick(state: AddCategoryModal) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("createCategory")
    let form = dom.document.getElementById("add-category-form")
    let formData = newFormData(form)

    ajaxPost(uri, @[], formData.to(cstring),
             (s: int, r: kstring) => onAddCategoryPost(s, r, state))

  proc setModalShown*(state: AddCategoryModal, visible: bool) =
    state.modalShown = visible
    state.markDirty()

  proc onModalClose(state: AddCategoryModal, ev: Event, n: VNode) =
    state.setModalShown(false)
    ev.preventDefault()

  proc render*(state: AddCategoryModal): VNode =
    result = buildHtml():
      tdiv(class=class({"active": state.modalShown}, "modal modal-sm")):
        a(href="", class="modal-overlay", "aria-label"="close",
          onClick=(ev: Event, n: VNode) => onModalClose(state, ev, n))
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
