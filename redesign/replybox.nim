when defined(js):
  import strformat

  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, threadlist

  type
    ReplyBox* = ref object
      preview: bool

  proc newReplyBox*(): ReplyBox =
    ReplyBox()

  proc render*(state: ReplyBox, thread: Thread): VNode =
    result = buildHtml():
      tdiv(class="information no-border"):
        tdiv(class="information-icon"):
          italic(class="fas fa-reply")
        tdiv(class="information-main", style=style(StyleAttr.width, "100%")):
          tdiv(class="information-title"):
            # text fmt("Replying to \"{thread.topic}\"")
          # tdiv(class="information-content"):
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