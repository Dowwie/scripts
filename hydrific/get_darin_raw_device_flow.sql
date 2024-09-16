COPY (
    SELECT 
     device_id,
     (EXTRACT(EPOCH FROM timestamp) * 10000)::bigint as "timestamp",
    tdiff * -0.00094 as flow_lpm 
    FROM raw 
    WHERE device_id = 'ff5d6887-1b6b-4ef7-b9eb-84be841129bd'
) TO STDOUT WITH (FORMAT CSV, DELIMITER '|', NULL '¤');
