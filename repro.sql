CREATE SCHEMA bespoke;

-- 1. TRAIT: The Universal Label
-- Defines the high-level categories (Domains) this label can attach to.
-- e.g. domains = ['party', 'deal']
CREATE TABLE bespoke.trait (
    "id"          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "tenant_id"   UUID NOT NULL,
    "name"        TEXT NOT NULL,
    "slug"        TEXT NOT NULL,

    -- "Where can I use this?"
    -- e.g. ['party', 'deal', 'collateral']
    "domains"     TEXT[] NOT NULL DEFAULT '{}',

    UNIQUE ("tenant_id", "slug")
);

-- 2. SCHEMA: The Rules
-- Defines the shape of the data for a specific Domain + Sub-Domain combination.
CREATE TABLE bespoke.schema (
    "id"          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "trait_id"    UUID NOT NULL REFERENCES bespoke.trait("id") ON DELETE CASCADE,

    -- DOMAIN: The High-Level Category (Matches one of the trait's domains)
    -- e.g. 'party'
    "domain"      TEXT NOT NULL,

    -- SUB_DOMAIN: The Specific Variation (Discriminator)
    -- e.g. 'entity' vs 'contact'.
    -- NULL means "Applies to the entire domain" (like for 'deal').
    "sub_domain"  TEXT,

    "json_schema" JSONB NOT NULL DEFAULT '{}',
    "version"     INT NOT NULL DEFAULT 1,
    "is_active"   BOOLEAN NOT NULL DEFAULT true,

    -- Rule: You can't have two active V1 schemas for "Party -> Entity"
    UNIQUE ("trait_id", "domain", "sub_domain", "version")
);

-- 3. STATE: The Data
-- The storage table remains generic.
CREATE TABLE bespoke.state (
    "id"          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "schema_id"   UUID NOT NULL REFERENCES bespoke.schema("id"),

    -- TARGET_ID: The Pointer.
    -- This is the specific UUID of the row in the 'party' or 'deal' table.
    "target_id"   UUID NOT NULL,

    "data"        JSONB NOT NULL DEFAULT '{}',
    "updated_at"  TIMESTAMPTZ DEFAULT now(),

    UNIQUE ("target_id", "schema_id")
);

CREATE TABLE bespoke.assignment (
    "id"          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "trait_id"    UUID NOT NULL REFERENCES bespoke.trait("id") ON DELETE CASCADE,
    "target_id"   UUID NOT NULL, -- The Party or Deal

    "created_at"  TIMESTAMPTZ DEFAULT now(),

    -- STATE TOGGLE
    -- NULL = Active / Visible
    -- Date = "Soft Deleted" (Grayed out in UI)
    "removed_at"  TIMESTAMPTZ,

    -- SIMPLE CONSTRAINT
    -- Enforces: "You can only have this trait assigned ONCE."
    -- If you remove it and re-add it, you are just updating this single row.
    UNIQUE ("target_id", "trait_id")
);
