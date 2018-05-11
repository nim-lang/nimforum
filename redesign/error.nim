import options
type
  PostError* = object
    errorFields*: seq[string] ## IDs of the fields with an error.
    message*: string

when defined(js):
  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils

  proc renderError*(message: string): VNode =
    result = buildHtml():
      tdiv(class="empty error"):
        tdiv(class="empty icon"):
          italic(class="fas fa-bug fa-5x")
        p(class="empty-title h5"):
          text message
        p(class="empty-subtitle"):
          text "Please report this issue to us so we can fix it!"
        tdiv(class="empty-action"):
          a(href="https://github.com/nim-lang/nimforum/issues", target="_blank"):
            button(class="btn btn-primary"):
              text "Report issue"

  proc genFormField*(error: Option[PostError], name, label, typ: string,
                     isLast: bool): VNode =
    let hasError =
      not error.isNone and (
        name in error.get().errorFields or
        error.get().errorFields.len == 0)
    result = buildHtml():
      tdiv(class=class({"has-error": hasError}, "form-group")):
        label(class="form-label", `for`=name):
          text label
        input(class="form-input", `type`="text", name=name)

        if not error.isNone:
          let e = error.get()
          if (e.errorFields.len == 1 and e.errorFields[0] == name) or isLast:
            p(class="form-input-hint"):
              text e.message