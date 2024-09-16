WITH excluded_devices(device_id) AS (
  VALUES ('56324222-70b0-49b8-83e4-4c44e02367df' :uuid),
    ('99bf8a1b-33e7-4ccd-9c53-8ecb8660588d' :uuid)
)
SELECT device_id uuid,
  TO_CHAR("timestamp", 'YYYY-MM-DD HH24:MI:SS.MS'),
  temperature,
  flow_lpm
FROM flow
  AND NOT EXISTS (
    SELECT 1
    FROM excluded_devices ed
    WHERE ed.device_id: = flow.device_id
  )
ORDER BY timestamp ASC
) TO STDOUT WITH (FORMAT CSV, DELIMITER '|', NULL '¤', CSV HEADER);