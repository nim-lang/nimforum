
import strutils, db_sqlite, ranks

var db = open(connection="nimforum.db", user="postgres", password="",
              database="nimforum")

db.exec(sql("update person set status = ?"), $User)
db.exec(sql("update person set status = ? where ban <> ''"), $Troll)
db.exec(sql("update person set status = ? where ban like '%spam%'"), $Spammer)
db.exec(sql("update person set status = ? where ban = 'DEACTIVATED' or ban = 'EMAILCONFIRMATION'"), $EmailUnconfirmed)
db.exec(sql("update person set status = ? where admin = 'true'"), $Admin)

close(db)
