import options, httpcore
type
  PostError* = object
    errorFields*: seq[string] ## IDs of the fields with an error.
    message*: string

when defined(js):
  import json
  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils

  proc render404*(): VNode =
    result = buildHtml():
      tdiv(class="empty error"):
        tdiv(class="empty icon"):
          italic(class="fas fa-bug fa-5x")
        p(class="empty-title h5"):
          text "404 Not Found"
        p(class="empty-subtitle"):
          text "Cannot find what you are looking for, it might have been " &
               "deleted. Sorry!"
        tdiv(class="empty-action"):
          a(href="/", onClick=anchorCB):
            button(class="btn btn-primary"):
              text "Go back home"

  proc renderError*(message: string, status: HttpCode): VNode =
    if status == Http404:
      return render404()

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
        input(class="form-input", `type`=typ, name=name)

        if not error.isNone:
          let e = error.get()
          if (e.errorFields.len == 1 and e.errorFields[0] == name) or
             (isLast and e.errorFields.len == 0):
            p(class="form-input-hint"):
              text e.message

  template postFinished*(onSuccess: untyped): untyped =
    state.loading = false
    let status = httpStatus.HttpCode
    if status == Http200:
      onSuccess
    else:
      # TODO: Karax should pass the content-type...
      try:
        let parsed = parseJson($response)
        let error = to(parsed, PostError)

        state.error = some(error)
      except:
        kout(getCurrentExceptionMsg().cstring)
        state.error = some(PostError(
          errorFields: @[],
          message: "Unknown error occurred."
        ))