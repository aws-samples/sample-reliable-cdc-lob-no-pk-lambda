# Technical and security review

## Result

The package is structurally aligned with the blog's corrected CDC design after the changes in this reviewed version.

## Verified design points

- Requires a stable, non-null, unique `SourceRecordID`.
- Uses `sys.fn_cdc_get_min_lsn`, `sys.fn_cdc_get_max_lsn`, and `sys.fn_cdc_increment_lsn`.
- Uses `cdc.fn_cdc_get_all_changes_<capture_instance>` with `N'all'`.
- Reads a complete inclusive LSN window rather than advancing a checkpoint through a `TOP` subset of a transaction.
- Detects a CDC-retention gap before reading changes.
- Treats an empty poll separately.
- Orders by `__$start_lsn, __$seqval`.
- Reduces repeated keys to the final ordered change before applying target DML.
- Uses final DELETE or UPSERT behavior.
- Commits target DML and `last_to_lsn` checkpoint atomically.
- Does not use `fn_cdc_get_net_changes`, which is not appropriate for the stated no-PK/no-unique-index source scenario.
- Validates interpolated capture-instance and target-table identifiers.
- Uses Secrets Manager rather than embedding credentials.
- Configures certificate validation in the sample connection strings.
- Documents reserved concurrency of one.

## Publication blockers / items requiring environment confirmation

1. **Deployment artifact**: `pyodbc` and PostgreSQL client dependencies require a Lambda-compatible Linux build. `pyodbc` additionally requires an ODBC runtime/driver. See `DEPLOYMENT.md`.
2. **Initial DMS/full-load handoff**: the repository intentionally does not invent a customer-specific handoff. The publication must document the actual runbook used to establish `migration_start_lsn`, retain CDC history through the baseline load, seed the checkpoint, and begin catch-up.
3. **CDC retention sizing**: confirm retention is long enough for the actual initial-load plus catch-up duration.
4. **Source/target column mapping**: `LargeTextValue` and `ModifiedAt` are generic sample columns. Confirm the public sample schema is intentionally generic and matches the blog.
5. **Target identifier type**: the sample target currently uses `bigint` for `source_record_id`. Change it if the public logical identifier is not numeric.
6. **Dependency versions**: pin versions only after testing the chosen Lambda runtime and architecture. Do not publish untested version pins merely for appearance.
7. **TLS trust**: test certificate validation from the deployed Lambda environment to both endpoints.
8. **Least privilege**: document/test the exact database grants and Lambda IAM permissions used by the deployable sample if those are added.
9. **Large windows**: the current sample uses `max_lsn` as the endpoint. For a very high-volume workload, memory/runtime limits may require a safe complete-LSN window-sizing strategy. Do not reintroduce a row-count `TOP` checkpoint bug when adding such limits.
10. **DDL drift**: schema changes require explicit operational handling and testing.

## Change made during review

The SQL Server TVF invocation now declares `@from_lsn` and `@to_lsn` variables before calling the CDC TVF instead of relying on parameter markers directly in the TVF argument list. This keeps the LSN parameters explicitly typed as `binary(10)`.

## Recommended tests before publication

- Duplicate and NULL `SourceRecordID` rejection.
- INSERT, UPDATE, DELETE independently.
- Multiple updates to the same key in one window.
- DELETE then INSERT for the same key in one window.
- INSERT then DELETE for the same key in one window.
- Multiple rows sharing one commit LSN.
- Empty poll.
- Forced failure before commit and verification that neither data nor checkpoint commits.
- Retention-gap failure.
- Lambda retry of the same window after rollback.
- Large `nvarchar(max)` payload.
- Unicode/multilingual/supplementary characters.
- TLS certificate validation.
- Full-load/CDC catch-up handoff.


## Reviewed-v3 corrections

- Fixed the visible escaped README paragraph break.
- Added explicit NULL-LSN guards with a clear CDC-not-ready error.
- Added a clearly marked `@last_to_lsn` placeholder declaration to the reference SQL.
- Documented `ODBC_DRIVER` and `PGSSLMODE` as optional overrides.
- Clarified `pyodbc` versus `psycopg2-binary` deployment requirements.

Dependency versions remain intentionally unpinned until the publication Lambda runtime and architecture are selected and tested.
