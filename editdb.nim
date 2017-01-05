
import strutils, db_sqlite, ranks

var db = open(connection="nimforum.db", user="postgres", password="",
              database="nimforum")

when false:
  db.exec(sql("update person set status = ?"), $User)
  db.exec(sql("update person set status = ? where ban <> ''"), $Troll)
  db.exec(sql("update person set status = ? where ban like '%spam%'"), $Spammer)
  db.exec(sql("update person set status = ? where ban = 'DEACTIVATED' or ban = 'EMAILCONFIRMATION'"), $EmailUnconfirmed)
  db.exec(sql("update person set status = ? where admin = 'true'"), $Admin)
else:
  db.exec sql"create index PersonStatusIdx on person(status);"
  db.exec sql"create index PostByAuthorIdx on post(thread, author);"
  db.exec sql"update person set name = 'cheatfate' where name = 'ka';"


close(db)
