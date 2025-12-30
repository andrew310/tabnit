ALTER TABLE "users" ADD COLUMN "email" TEXT;

-- SAFEGUARD: The following line drops data. Uncomment to execute.

-- ALTER TABLE "posts" DROP COLUMN "content";

CREATE TABLE "comments" (
  "id" UUID NOT NULL PRIMARY KEY,
  "post_id" UUID REFERENCES "posts"("id"),
  "body" TEXT NOT NULL
);