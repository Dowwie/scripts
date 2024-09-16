SET timescaledb.enable_tiered_reads = true;
COPY (
select device_id, 
   '[' || rtrim(rtrim(array_to_string(
      ARRAY_AGG(
        '(' || tag.id || ',' || tag.annotation || ',' || 
        TO_CHAR(timestamp, 'YYYY-MM-DD"T"HH24:MI:SS.US') || ')'
      ), 
      ','), 
    ','), ')') || ']' AS tag_times_and_ids
FROM tag
WHERE level = 1
AND EXTRACT(YEAR FROM timestamp) = 2024
AND annotation in ('Toilet', 'Faucet', 'Shower')
AND EXTRACT(MONTH FROM timestamp) not in (1,2)
and device_id not in ('56324222-70b0-49b8-83e4-4c44e02367df'::uuid, '99bf8a1b-33e7-4ccd-9c53-8ecb8660588d'::uuid)
GROUP BY device_id
ORDER BY array_length(array_agg(timestamp), 1) DESC
) TO STDOUT WITH (FORMAT CSV, DELIMITER '|', NULL '¤');
SET timescaledb.enable_tiered_reads = false;
