CREATE SCHEMA IF NOT EXISTS cdc_sync;

CREATE TABLE IF NOT EXISTS public.large_object_records (
    source_record_id bigint PRIMARY KEY,
    large_text_value text,
    modified_at timestamptz
);

CREATE TABLE IF NOT EXISTS cdc_sync.cdc_state (
    capture_instance text PRIMARY KEY,
    last_to_lsn bytea NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Seed last_to_lsn with the raw 10-byte value returned by
-- sys.fn_cdc_decrement_lsn(migration_start_lsn), where migration_start_lsn
-- has already been established as a valid CDC boundary.
