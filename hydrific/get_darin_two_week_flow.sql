COPY (
    -- we don't want to cut the first segment off so we gracefully handle that in this logic
  WITH start_point AS (
    SELECT timestamp AS start_timestamp
    FROM (
      SELECT
        timestamp,
        SUM(CASE WHEN flow_lpm < 1 THEN 1 ELSE 0 END) OVER (
          ORDER BY timestamp ASC
          ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS low_flow_count,
        ROW_NUMBER() OVER (ORDER BY timestamp ASC) AS rn
      FROM flow
      WHERE device_id = 'ff5d6887-1b6b-4ef7-b9eb-84be841129bd'
        AND timestamp >= CURRENT_TIMESTAMP - INTERVAL '2 weeks'
    ) subquery
    WHERE low_flow_count = 3
    ORDER BY rn
    LIMIT 1
  )
  SELECT
    device_id,
    (EXTRACT(EPOCH FROM timestamp) * 10000)::bigint as "timestamp_ms",
    flow_lpm
  FROM flow
  WHERE device_id = 'ff5d6887-1b6b-4ef7-b9eb-84be841129bd'
    AND timestamp >= (SELECT start_timestamp FROM start_point)
  ORDER BY timestamp ASC
) TO STDOUT WITH (FORMAT CSV, DELIMITER '|', NULL '¤');
