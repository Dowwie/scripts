SET timescaledb.enable_tiered_reads = true;
COPY (
select id, to_char(timestamp, 'YYYY-MM-DD"T"HH24:MI:SS.US') as timestamp, annotation
  from tag
 where level = 1
AND EXTRACT(YEAR FROM timestamp) = 2024
and annotation in ('Toilet', 'Faucet', 'Shower')
and EXTRACT(MONTH FROM timestamp) not in (1,2)
and device_id not in ('56324222-70b0-49b8-83e4-4c44e02367df'::uuid, '99bf8a1b-33e7-4ccd-9c53-8ecb8660588d'::uuid)
) TO STDOUT WITH (FORMAT CSV, DELIMITER '|', NULL '¤');
SET timescaledb.enable_tiered_reads = false;
