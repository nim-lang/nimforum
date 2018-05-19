when defined(js):
  import httpcore, options, sugar, json

  include karax/prelude
  import karax/kajax

  import replybox, post, karaxutils, threadlist, error

  type
    OnEditPosted* = proc (id: int, content: string, subject: Option[string])

    EditBox* = ref object
      box: ReplyBox
      post: Post
      rawContent: Option[kstring] ## The raw rst for a post (needs to be loaded)
      loading: bool
      status: HttpCode
      error: Option[PostError]
      onEditPosted: OnEditPosted
      onEditCancel: proc ()

  proc newEditBox*(onEditPosted: OnEditPosted, onEditCancel: proc ()): EditBox =
    EditBox(
      box: newReplyBox(nil),
      onEditPosted: onEditPosted,
      onEditCancel: onEditCancel,
      status: Http200
    )

  proc onRawContent(httpStatus: int, response: kstring, state: EditBox) =
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    state.rawContent = some(response)
    state.box.setText(state.rawContent.get())

  proc onEditPost(httpStatus: int, response: kstring, state: EditBox) =
    postFinished:
      state.onEditPosted(
        state.post.id,
        $response,
        none[string]()
      )

  proc save(state: EditBox) =
    if state.loading:
      # TODO: Weird behaviour: onClick handler gets called 80+ times.
      return
    state.loading = true
    state.error = none[PostError]()

    let formData = newFormData()
    formData.append("msg", state.box.getText())
    formData.append("postId", $state.post.id)
    # TODO: Subject
    let uri = makeUri("/updatePost")
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) => onEditPost(s, r, state))

  proc render*(state: EditBox, post: Post): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve raw post", state.status)

    if state.rawContent.isNone() or state.post.id != post.id:
      state.post = post
      state.rawContent = none[kstring]()
      var params = @[("id", $post.id)]
      let uri = makeUri("post.rst", params)
      ajaxGet(uri, @[], (s: int, r: kstring) => onRawContent(s, r, state))

      return buildHtml(tdiv(class="loading"))

    result = buildHtml():
      tdiv(class="edit-box"):
        renderContent(
          state.box,
          none[Thread](),
          none[Post]()
        )

        if state.error.isSome():
          span(class="text-error"):
            text state.error.get().message

        tdiv(class="edit-buttons"):
          tdiv(class="reply-button"):
            button(class="btn btn-link",
                   onClick=(e: Event, n: VNode) => (state.onEditCancel())):
              text " Cancel"
          tdiv(class="save-button"):
            button(class=class({"loading": state.loading}, "btn btn-primary"),
                   onClick=(e: Event, n: VNode) => state.save()):
              italic(class="fas fa-check")
              text " Save"