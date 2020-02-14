when defined(js):
  import strformat, options, httpcore, json, sugar

  from dom import getElementById, scrollIntoView, setTimeout

  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, threadlist, post, error, user

  type
    ReplyBox* = ref object
      shown: bool
      text: kstring
      preview: bool
      loading: bool
      error: Option[PostError]
      rendering: Option[kstring]
      onPost: proc (id: int)

  proc newReplyBox*(onPost: proc (id: int)): ReplyBox =
    ReplyBox(
      text: "",
      onPost: onPost
    )

  proc performScroll() =
    let replyBox = dom.document.getElementById("reply-box")
    replyBox.scrollIntoView()

  proc show*(state: ReplyBox) =
    # Scroll to the reply box.
    if not state.shown:
      # TODO: It would be nice for Karax to give us an event when it renders
      # things. That way we can remove this crappy hack.
      discard dom.window.setTimeout(performScroll, 50)
    else:
      performScroll()

    state.shown = true

  proc getText*(state: ReplyBox): kstring = state.text
  proc setText*(state: ReplyBox, text: kstring) = state.text = text

  proc onPreviewPost(httpStatus: int, response: kstring, state: ReplyBox) =
    postFinished:
      echo response
      state.rendering = some[kstring](response)

  proc onPreviewClick(e: Event, n: VNode, state: ReplyBox) =
    state.preview = true
    state.loading = true
    state.error = none[PostError]()
    state.rendering = none[kstring]()

    let formData = newFormData()
    formData.append("msg", state.text)
    let uri = makeUri("/preview")
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) => onPreviewPost(s, r, state))

  proc onMessageClick(e: Event, n: VNode, state: ReplyBox) =
    state.preview = false
    state.error = none[PostError]()

  proc onReplyPost(httpStatus: int, response: kstring, state: ReplyBox) =
    postFinished:
      state.text = ""
      state.shown = false
      state.onPost(parseJson($response).getInt())

  proc onReplyClick(e: Event, n: VNode, state: ReplyBox,
                    thread: Thread, replyingTo: Option[Post]) =
    state.loading = true
    state.error = none[PostError]()

    let formData = newFormData()
    formData.append("msg", state.text)
    formData.append("threadId", $thread.id)
    if replyingTo.isSome:
      formData.append("replyingTo", $replyingTo.get().id)
    let uri = makeUri("/createPost")
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) => onReplyPost(s, r, state))

  proc onCancelClick(e: Event, n: VNode, state: ReplyBox) =
    # TODO: Double check reply box contents and ask user whether to discard.
    state.shown = false

  proc onChange(e: Event, n: VNode, state: ReplyBox) =
    # TODO: Please document this better in Karax.
    state.text = n.value

  proc renderContent*(state: ReplyBox, thread: Option[Thread],
                      post: Option[Post]): VNode =
    result = buildHtml():
      tdiv(class="panel"):
        tdiv(class="panel-nav"):
          ul(class="tab tab-block"):
            li(class=class({"active": not state.preview}, "tab-item"),
               onClick=(e: Event, n: VNode) =>
                  onMessageClick(e, n, state)):
              a(class="c-hand"):
                text "Message"
            li(class=class({"active": state.preview}, "tab-item"),
               onClick=(e: Event, n: VNode) =>
                  onPreviewClick(e, n, state)):
              a(class="c-hand"):
                text "Preview"
        tdiv(class="panel-body"):
          if state.preview:
            if state.loading:
              tdiv(class="loading")
            elif state.rendering.isSome():
              verbatim(state.rendering.get())
          else:
            textarea(id="reply-textarea",
                     class="form-input post-text-area", rows="5",
                     onChange=(e: Event, n: VNode) =>
                        onChange(e, n, state),
                     value=state.text)
            a(href=makeUri("/about/rst"), target="blank_"):
              text "Styling with RST is supported"

          if state.error.isSome():
            span(class="text-error",
                 style=style(StyleAttr.marginTop, "0.4rem")):
              text state.error.get().message

        if thread.isSome:
          tdiv(class="panel-footer"):
            button(class=class(
                     {"loading": state.loading},
                     "btn btn-primary float-right"
                   ),
                   onClick=(e: Event, n: VNode) =>
                      onReplyClick(e, n, state, thread.get(), post)):
              text "Reply"
            button(class="btn btn-link float-right",
                   onClick=(e: Event, n: VNode) =>
                      onCancelClick(e, n, state)):
              text "Cancel"

  proc render*(state: ReplyBox, thread: Thread, post: Option[Post],
               hasMore: bool): VNode =
    if not state.shown:
      return buildHtml(tdiv(id="reply-box"))

    result = buildHtml():
      tdiv(class=class({"no-border": hasMore}, "information"), id="reply-box"):
        tdiv(class="information-icon"):
          italic(class="fas fa-reply")
        tdiv(class="information-main", style=style(StyleAttr.width, "100%")):
          tdiv(class="information-title"):
            if post.isNone:
              text fmt("Replying to \"{thread.topic}\"")
            else:
              text "Replying to "
              renderUserMention(post.get().author)
              tdiv(class="post-buttons",
                   style=style(StyleAttr.marginTop, "-0.3rem")):
                a(href=renderPostUrl(post.get(), thread)):
                  button(class="btn"):
                    italic(class="fas fa-arrow-up")
          tdiv(class="information-content"):
            renderContent(state, some(thread), post)
