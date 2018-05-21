import db_sqlite, strutils

let origFile = "nimforum.db-21-05-18"
let targetFile = "nimforum-blank.db"

let orig = open(connection=origFile, user="", password="",
                database="nimforum")
let target = open(connection=targetFile, user="", password="",
                database="nimforum")

block:
  let fields = "id, name, views, modified"
  for thread in getAllRows(orig, sql("select $1 from thread;" % fields)):
    target.exec(
      sql("""
      insert into thread($1)
      values (?, ?, ?, ?)
      """ % fields),
      thread
    )

block:
  let fields = "id, name, password, email, creation, salt, status, lastOnline"
  for person in getAllRows(orig, sql("select $1 from person;" % fields)):
    target.exec(
      sql("""
      insert into person($1)
      values (?, ?, ?, ?, ?, ?, ?, ?)
      """ % fields),
      person
    )

block:
  let fields = "id, author, ip, content, thread, creation"
  for post in getAllRows(orig, sql("select $1 from post;" % fields)):
    target.exec(
      sql("""
      insert into post($1)
      values (?, ?, ?, ?, ?, ?)
      """ % fields),
      post
    )

block:
  let fields = "id, name"
  for t in getAllRows(orig, sql("select $1 from thread_fts;" % fields)):
    target.exec(
      sql("""
      insert into thread_fts($1)
      values (?, ?)
      """ % fields),
      t
    )

block:
  let fields = "id, content"
  for p in getAllRows(orig, sql("select $1 from post_fts;" % fields)):
    target.exec(
      sql("""
      insert into post_fts($1)
      values (?, ?)
      """ % fields),
      p
    )

echo("Imported!")