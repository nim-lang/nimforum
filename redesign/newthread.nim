when defined(js):
  import sugar, httpcore, options, json
  import dom except Event

  include karax/prelude
  import karax / [kajax, kdom]

  import error, replybox, threadlist, post
  import karaxutils

  type
    NewThread* = ref object
      loading: bool
      error: Option[PostError]
      replyBox: ReplyBox

  proc onCreatePost(httpStatus: int, response: kstring, state: NewThread) =
    postFinished:
      # TODO
      discard

  proc onCreateClick(ev: Event, n: VNode, state: NewThread) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("login")
    # TODO: This is a hack, karax should support this.
    let formData = newFormData()
    #formData.append("" TODO
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) => onCreatePost(s, r, state))

  proc newNewThread*(): NewThread =
    NewThread(
      replyBox: newReplyBox(nil)
    )

  proc render*(state: NewThread): VNode =
    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(id="new-thread"):
          tdiv(class="title"):
            p(): text "New Thread"
          tdiv(class="content"):
            input(class="form-input", `type`="text", name="username",
                  placeholder="Type the title here")
            renderContent(state.replyBox, none[Thread](), none[Post]())
          tdiv(class="footer"):
            button(class=class(
                    {"loading": state.loading},
                    "btn btn-primary"
                   ),
                   onClick=(ev: Event, n: VNode) =>
                    (onCreateClick(ev, n, state))):
              text "Create thread"