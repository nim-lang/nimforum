when defined(js):
  import sugar, httpcore, options, json
  import dom except Event
  import jsffi except `&`

  include karax/prelude
  import karax / [kajax, kdom]

  import error, post, threadlist, user
  import karaxutils

  type
    DeleteKind* = enum
      DeleteUser, DeletePost, DeleteThread

    DeleteModal* = ref object
      shown: bool
      loading: bool
      onDeletePost: proc (post: Post)
      onDeleteThread: proc (thread: Thread)
      onDeleteUser: proc (user: User)
      error: Option[PostError]
      case kind: DeleteKind
      of DeleteUser:
        user: User
      of DeletePost:
        post: Post
      of DeleteThread:
        thread: Thread

  proc onDeletePost(httpStatus: int, response: kstring, state: DeleteModal) =
    postFinished:
      state.shown = false
      case state.kind
      of DeleteUser:
        state.onDeleteUser(state.user)
      of DeletePost:
        state.onDeletePost(state.post)
      of DeleteThread:
        state.onDeleteThread(state.thread)

  proc onDelete(ev: Event, n: VNode, state: DeleteModal) =
    state.loading = true
    state.error = none[PostError]()

    let uri =
      case state.kind
      of DeleteUser:
        makeUri("/deleteUser")
      of DeleteThread:
        makeUri("/deleteThread")
      of DeletePost:
        makeUri("/deletePost")
    # TODO: This is a hack, karax should support this.
    let formData = newFormData()
    case state.kind
    of DeleteUser:
      formData.append("username", state.user.name)
    of DeletePost:
      formData.append("id", $state.post.id)
    of DeleteThread:
      formData.append("id", $state.thread.id)
    ajaxPost(uri, @[], formData.to(cstring),
             (s: int, r: kstring) => onDeletePost(s, r, state))

  proc onClose(ev: Event, n: VNode, state: DeleteModal) =
    state.shown = false
    ev.preventDefault()

  proc newDeleteModal*(
    onDeletePost: proc (post: Post),
    onDeleteThread: proc (thread: Thread),
    onDeleteUser: proc (user: User),
  ): DeleteModal =
    DeleteModal(
      shown: false,
      onDeletePost: onDeletePost,
      onDeleteThread: onDeleteThread,
      onDeleteUser: onDeleteUser,
    )

  proc show*(state: DeleteModal, thing: User | Post | Thread) =
    state.shown = true
    state.error = none[PostError]()
    when thing is User:
      state.kind = DeleteUser
      state.user = thing
    when thing is Post:
      state.kind = DeletePost
      state.post = thing
    when thing is Thread:
      state.kind = DeleteThread
      state.thread = thing

  proc render*(state: DeleteModal): VNode =
    result = buildHtml():
      tdiv(class=class({"active": state.shown}, "modal modal-sm"),
           id="delete-modal"):
        a(href="", class="modal-overlay", "aria-label"="close",
          onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
        tdiv(class="modal-container"):
          tdiv(class="modal-header"):
            a(href="", class="btn btn-clear float-right",
              "aria-label"="close",
              onClick=(ev: Event, n: VNode) => onClose(ev, n, state))
            tdiv(class="modal-title h5"):
              text "Delete"
          tdiv(class="modal-body"):
            tdiv(class="content"):
              p():
                text "Are you sure you want to delete this "
                case state.kind
                of DeleteUser:
                  text "user account?"
                of DeleteThread:
                  text "thread?"
                of DeletePost:
                  text "post?"
          tdiv(class="modal-footer"):
            if state.error.isSome():
              p(class="text-error"):
                text state.error.get().message

            button(class=class(
                    {"loading": state.loading},
                    "btn btn-primary delete-btn"
                   ),
                   onClick=(ev: Event, n: VNode) => onDelete(ev, n, state)):
              italic(class="fas fa-trash-alt")
              text " Delete"
            button(class="btn cancel-btn",
                   onClick=(ev: Event, n: VNode) => (state.shown = false)):
              text "Cancel"
