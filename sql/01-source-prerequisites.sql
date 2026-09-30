-- The first query must return no rows.
SELECT SourceRecordID, COUNT(*) AS duplicate_count
FROM dbo.LargeObjectRecords
GROUP BY SourceRecordID
HAVING COUNT(*) > 1;

-- This query must return zero.
SELECT COUNT(*) AS null_source_record_ids
FROM dbo.LargeObjectRecords
WHERE SourceRecordID IS NULL;
