when defined(js):
  import httpcore, options, sugar

  include karax/prelude
  import karax/kajax

  import replybox, post, karaxutils, threadlist

  type
    EditBox* = ref object
      box: ReplyBox
      post: Option[Post]
      rawContent: Option[kstring] ## The raw rst for a post (needs to be loaded)
      status: HttpCode

  proc newEditBox*(): EditBox =
    EditBox(
      box: newReplyBox(nil)
    )

  proc onRawContent(httpStatus: int, response: kstring, state: EditBox) =
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    state.rawContent = some(response)

  proc render*(state: EditBox, post: Post): VNode =
    if state.post.isNone() or state.post.get().id != post.id:
      state.post = some(post)
      var params = @[("id", $post.id)]
      let uri = makeUri("post.rst", params)
      ajaxGet(uri, @[], (s: int, r: kstring) => onRawContent(s, r, state))

      return buildHtml(tdiv(class="loading"))

    state.box.setText(state.rawContent.get())
    result = buildHtml():
      tdiv(class="edit-box"):
        renderContent(
          state.box,
          none[Thread](),
          none[Post]()
        )