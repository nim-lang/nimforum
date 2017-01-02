
type
  Rank* = enum ## serialized as 'status'
    Spammer          ## spammer: every post is invisible
    Troll            ## troll: cannot write new posts
    EmailUnconfirmed ## member with unconfirmed email address
    Moderated        ## new member: posts manually reviewed before everybody
                     ## can see them
    User             ## Ordinary user
    Moderator        ## Moderator: can ban/moderate users
    Admin            ## Admin: can do everything
