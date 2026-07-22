
type
  Category* = object
    id*: int
    name*: string
    description*: string
    color*: string
    numTopics*: int

  CategoryList* = ref object
    categories*: seq[Category]

  CategoryEvent* = proc (category: Category) {.closure.}
  CategoryChangeEvent* = proc (oldCategory: Category, newCategory: Category) {.closure.}

const categoryDescriptionCharLimit = 250

proc cmpNames*(cat1: Category, cat2: Category): int =
  cat1.name.cmp(cat2.name)

when defined(js):
  include karax/prelude
  import karax / [vstyles]
  import karaxutils

  proc render*(category: Category, compact=true): VNode =
    if category.name.len == 0:
      return buildHtml():
        span()

    result = buildhtml(tdiv):
      tdiv(class="category-status"):
        tdiv(class="category",
             title=category.description,
             "data-color"="#" & category.color):
          tdiv(class="category-color",
               style=style(
                 (StyleAttr.border,
                  kstring"0.25rem solid #" & category.color)
          ))
          span(class="category-name"):
            a(href=makeUri("/c/" & $category.id)):
              text category.name
          if not compact:
            span(class="topic-count"):
              text "× " & $category.numTopics
      if not compact:
        tdiv(class="category-description"):
          text category.description.limit(categoryDescriptionCharLimit)