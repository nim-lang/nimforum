
import strutils, db_sqlite

var db = open(connection="nimforum.db", user="postgres", password="",
              database="nimforum")

db.exec(sql"""ALTER TABLE person add column
  lastOnline timestamp
""", [])

close(db)
