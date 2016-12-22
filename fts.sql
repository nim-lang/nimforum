SELECT
        thread.id AS thread_id,
        thread.name AS thread,
        post.id AS post_id,
        CASE what WHEN 1
            THEN snippet(post_fts, '<b>', '</b>', '...', what)
            ELSE post_fts.header END AS header,
        CASE what WHEN 2
            THEN snippet(post_fts, '**', '**', '...', what, -45)
            ELSE SUBSTR(post_fts.content, 1, 200) END AS content,
        person.name AS author,
        cdate,
        post.author AS author_id,
        person.email AS email,
        what
    FROM post_fts JOIN (
    -- inner query, selects ids of matching posts, orders and limits them,
    -- so snippets only for limited count of posts are created (in outer query)
        SELECT * FROM (         -- a wrapper query to be able make GROUP BY
            SELECT id, post.creation AS cdate, thread, 1 AS what, post.author AS author
                FROM post_fts JOIN post USING(id)
                WHERE post_fts.header MATCH ?           -- query-w/o-author
                GROUP BY post.header
                HAVING SUBSTR(post.header,1,3)<>'Re:'
                    AND (? == 0 OR post.author == ?)    -- author, author
            UNION
            SELECT id, post.creation AS cdate, thread, 1 AS what, post.author AS author
                FROM post_fts JOIN post USING(id)
                WHERE post_fts.header MATCH ?           -- query
                GROUP BY post.header
                HAVING SUBSTR(post.header,1,3)<>'Re:'
            UNION
            SELECT id, post.creation AS cdate, thread, 2 AS what, post.author AS author
                FROM post_fts JOIN post USING(id)
                WHERE post_fts.content MATCH ?          -- query-w/o-author
                GROUP BY post_fts.id
                HAVING (? == 0 OR post.author == ?)     -- author, author
            UNION
            SELECT id, post.creation AS cdate, thread, 2 AS what, post.author AS author
                FROM post_fts JOIN post USING(id)
                WHERE post_fts.content MATCH ?          -- query
        )
        GROUP BY id
        ORDER BY what, cdate DESC
        LIMIT ? OFFSET (? - 1) * ?                      -- threads-per-page, pageNum, threads-per-page
    ) AS post USING(id)
        JOIN thread ON thread.id=thread
        JOIN person ON person.id=author
    WHERE post_fts MATCH ?                              -- query
ORDER BY cdate DESC
LIMIT 300 -- hardcoded limit just in case
;

