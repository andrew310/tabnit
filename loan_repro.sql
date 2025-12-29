CREATE TABLE "loan" (
  "ltv_at_origination_pct"        numeric(5,2),
  "created_at"                      timestamptz  NOT NULL DEFAULT now()
);
