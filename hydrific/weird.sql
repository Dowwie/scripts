
set timescaledb.enable_tiered_reads = true; 
SELECT
  "timestamp" AS "time",
  flow_lpm
FROM flow
WHERE
  "timestamp" BETWEEN '2024-03-22T11:47:04.066Z' AND '2024-03-22T11:49:31.047Z' AND
  device_id = '1ae468bc-7658-4fec-bd2a-40b9f70a76db'
ORDER BY 1;
set timescaledb.enable_tiered_reads = false;

