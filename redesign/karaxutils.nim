proc class*(classes: varargs[tuple[name: string, present: bool]],
           defaultClasses: string = ""): string =
  result = defaultClasses & " "
  for class in classes:
    if class.present: result.add(class.name & " ")