include karax/prelude
import karax / [vstyles, kajax, kdom]


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