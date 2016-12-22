SELECT
        thread.id AS thread_id,
        thread.name AS thread,
        post.id AS post_id,
        post.header AS header,
        SUBSTR(post.content, 1, 200) AS content,
        person.name AS author,
        post.creation AS cdate,
        post.author AS author_id,
        person.email AS email,
        CASE SUBSTR(post.header,1,3) WHEN 'Re:' THEN 2 ELSE 1 END AS what
FROM post   JOIN thread ON post.thread == thread.id
            JOIN person ON post.author == person.id
WHERE
        person.id == ?
ORDER BY cdate DESC
LIMIT ? OFFSET (? - 1) * ?
;