
type
  Category* = object
    id*: int
    name*: string
    description*: string
    color*: string

  CategoryList* = ref object
    categories*: seq[Category]

proc cmpNames*(cat1: Category, cat2: Category): int =
  cat1.name.cmp(cat2.name)

when defined(js):
  include karax/prelude
  import karax / [vstyles]

  proc render*(category: Category): VNode =
    result = buildHtml():
      if category.name.len >= 0:
        tdiv(class="category",
             title=category.description,
             "data-color"="#" & category.color):
          tdiv(class="category-color",
               style=style(
                 (StyleAttr.border,
                  kstring"0.3rem solid #" & category.color)
          ))
          text category.name
      else:
        span()
