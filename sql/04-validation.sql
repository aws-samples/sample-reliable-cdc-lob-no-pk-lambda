-- SQL Server source examples
SELECT COUNT_BIG(*) AS source_row_count
FROM dbo.LargeObjectRecords;

SELECT MIN(SourceRecordID), MAX(SourceRecordID)
FROM dbo.LargeObjectRecords;

-- Aurora target equivalents:
-- SELECT COUNT(*) FROM public.large_object_records;
-- SELECT MIN(source_record_id), MAX(source_record_id)
-- FROM public.large_object_records;

-- Also compare representative LOB values and multilingual/supplementary
-- characters at a coordinated comparison point.
