CREATE SCHEMA auth;

CREATE TYPE status AS ENUM ('pending', 'active', 'closed');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    status status DEFAULT 'pending'
);

/* 
   A comment block
*/

CREATE TABLE posts (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE, -- inline comment
    title TEXT NOT NULL,
    content TEXT
);