
import strutils, db_sqlite

var db = Open(connection="nimforum.db", user="postgres", password="", 
              database="nimforum")

db.exec(sql"""ALTER TABLE person add column
  lastOnline timestamp
""", [])

close(db)