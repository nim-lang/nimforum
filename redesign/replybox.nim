when defined(js):
  import strformat, options

  from dom import getElementById, scrollIntoView, setTimeout

  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, threadlist, post

  type
    ReplyBox* = ref object
      shown: bool
      preview: bool

  proc newReplyBox*(): ReplyBox =
    ReplyBox()

  proc performScroll() =
    let replyBox = dom.document.getElementById("reply-box")
    replyBox.scrollIntoView(false)

  proc show*(state: ReplyBox) =
    # Scroll to the reply box.
    if not state.shown:
      # TODO: It would be nice for Karax to give us an event when it renders
      # things. That way we can remove this crappy hack.
      discard dom.window.setTimeout(performScroll, 50)
    else:
      performScroll()

    state.shown = true

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
            tdiv(class="panel"):
              tdiv(class="panel-nav"):
                ul(class="tab tab-block"):
                  li(class=class({"active": not state.preview}, "tab-item")):
                    a(href="#"):
                      text "Message"
                  li(class=class({"active": state.preview}, "tab-item")):
                    a(href="#"):
                      text "Preview"
              tdiv(class="panel-body"):
                textarea(class="form-input", rows="5")
              tdiv(class="panel-footer"):
                button(class="btn btn-primary float-right"):
                  text "Reply"
                button(class="btn btn-link float-right"):
                  text "Cancel"