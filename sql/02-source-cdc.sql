-- Reference implementation for a complete inclusive LSN window.
DECLARE @min_lsn  binary(10) = sys.fn_cdc_get_min_lsn('dbo_LargeObjectRecords');
DECLARE @max_lsn  binary(10) = sys.fn_cdc_get_max_lsn();
DECLARE @from_lsn binary(10);
DECLARE @to_lsn   binary(10);

-- Replace this placeholder with the persisted checkpoint read from Aurora.
-- It must be the raw 10-byte SQL Server LSN for last_to_lsn.
DECLARE @last_to_lsn binary(10) = 0x00000000000000000000;
SET @from_lsn = sys.fn_cdc_increment_lsn(@last_to_lsn);
SET @to_lsn   = @max_lsn;

IF @from_lsn < @min_lsn
BEGIN
    RAISERROR('CDC gap: from_lsn < min_lsn', 16, 1);
    RETURN;
END;

IF @from_lsn > @to_lsn
BEGIN
    RETURN;
END;

SELECT *
FROM cdc.fn_cdc_get_all_changes_dbo_LargeObjectRecords(
    @from_lsn,
    @to_lsn,
    N'all'
)
ORDER BY __$start_lsn, __$seqval;

-- Initialization, after the runbook has already established a valid boundary:
-- SET @seed_last_to_lsn = sys.fn_cdc_decrement_lsn(@migration_start_lsn);
-- Invariant: increment(seed_last_to_lsn) = first LSN still to process.
