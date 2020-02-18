when defined(js):
  import sugar, httpcore, options, json
  import dom except Event
  import jsffi except `&`

  include karax/prelude
  import karax / [kajax, kdom]

  import error, replybox, threadlist, post, user
  import karaxutils, categorypicker

  type
    NewThread* = ref object
      loading: bool
      error: Option[PostError]
      replyBox: ReplyBox
      subject: kstring
      categoryPicker: CategoryPicker

  proc newNewThread*(): NewThread =
    NewThread(
      replyBox: newReplyBox(nil),
      subject: "",
      categoryPicker: newCategoryPicker()
    )

  proc onSubjectChange(e: Event, n: VNode, state: NewThread) =
    state.subject = n.value

  proc onCreatePost(httpStatus: int, response: kstring, state: NewThread) =
    postFinished:
      let j = parseJson($response)
      let response = to(j, array[2, int])
      navigateTo(renderPostUrl(response[0], response[1]))

  proc onCreateClick(ev: Event, n: VNode, state: NewThread) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("newthread")
    # TODO: This is a hack, karax should support this.
    let formData = newFormData()
    let categoryID = state.categoryPicker.selectedCategoryID

    formData.append("subject", state.subject)
    formData.append("msg", state.replyBox.getText())
    formData.append("categoryId", $categoryID)

    ajaxPost(uri, @[], formData.to(cstring),
             (s: int, r: kstring) => onCreatePost(s, r, state))

  proc render*(state: NewThread, currentUser: Option[User]): VNode =
    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(id="new-thread"):
          tdiv(class="title"):
            p(): text "New Thread"
          tdiv(class="content"):
            input(id="thread-title", class="form-input", `type`="text", name="subject",
                  placeholder="Type the title here",
                  oninput=(e: Event, n: VNode) => onSubjectChange(e, n, state))
            if state.error.isSome():
              p(class="text-error"):
                text state.error.get().message
            tdiv():
              label(class="d-inline-block form-label"):
                text "Category"
              render(state.categoryPicker, currentUser, compact=false)
            renderContent(state.replyBox, none[Thread](), none[Post]())
          tdiv(class="footer"):

            button(id="create-thread-btn",
                   class=class(
                     {"loading": state.loading},
                     "btn btn-primary"
                   ),
                   onClick=(ev: Event, n: VNode) =>
                    (onCreateClick(ev, n, state))):
              text "Create thread"
