when defined(js):
  import sugar, httpcore, options, json
  import dom except Event

  include karax/prelude
  import karax / [kajax, kdom]

  import error, replybox, threadlist, post
  import karaxutils

  type
    NewThreadModal* = ref object
      shown: bool
      loading: bool
      onNewThread: proc (threadId, postId: int)
      error: Option[PostError]
      replyBox: ReplyBox

  proc onCreatePost(httpStatus: int, response: kstring, state: NewThreadModal) =
    postFinished:
      state.shown = false
      state.onNewThread(0, 0) # TODO

  proc onCreateClick(ev: Event, n: VNode, state: NewThreadModal) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("login")
    # TODO: This is a hack, karax should support this.
    let formData = newFormData()
    #formData.append("" TODO
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) => onCreatePost(s, r, state))

  proc onClose(ev: Event, n: VNode, state: NewThreadModal) =
    state.shown = false
    ev.preventDefault()

  proc newNewThreadModal*(
    onNewThread: proc (threadId, postId: int)
  ): NewThreadModal =
    NewThreadModal(
      shown: false,
      onNewThread: onNewThread,
      replyBox: newReplyBox(nil)
    )

  proc show*(state: NewThreadModal) =
    state.shown = true

  proc render*(state: NewThreadModal): VNode =
    result = buildHtml():
      tdiv(class=class({"active": state.shown}, "modal modal-lg"),
           id="new-thread-modal"):
        a(href="", class="modal-overlay", "aria-label"="close",
          onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
        tdiv(class="modal-container"):
          tdiv(class="modal-header"):
            a(href="", class="btn btn-clear float-right",
              "aria-label"="close",
              onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
            tdiv(class="modal-title h5"):
              text "New Thread"
          tdiv(class="modal-body"):
            tdiv(class="content"):
              input(class="form-input", `type`="text", name="username",
                    placeholder="Type the title here")
              renderContent(state.replyBox, none[Thread](), none[Post]())

          tdiv(class="modal-footer"):
            button(class="btn",
                   onClick=(ev: Event, n: VNode) =>
                      onClose(ev, n, state)):
              text "Cancel"
            button(class=class(
                    {"loading": state.loading},
                    "btn btn-primary"
                   ),
                   onClick=(ev: Event, n: VNode) =>
                    (onCreateClick(ev, n, state))):
              text "Create thread"