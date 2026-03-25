SELECT p.plane_id, 
    NULL as plane_type,
    a.air_name AS base_airport, 
    COUNT(f.code_flight) AS flights_num,
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (f.actual_landing_time - f.actual_take_off_time))) / 3600, 2), 0) AS flight_time,
    CASE 
        WHEN COUNT(f.code_flight) > 0 THEN
            ROUND(COALESCE(SUM(EXTRACT(EPOCH FROM (f.actual_landing_time - f.actual_take_off_time))) / 3600, 0)/ COUNT(f.code_flight), 2)
        ELSE 0
    END AS avg_flight_time,
    MAX(f.actual_take_off_time) AS last_take_off,
    p.plane_state AS current_state
FROM Plane p
LEFT JOIN Airport a ON p.base_airport_id = a.airport_id
LEFT JOIN Flight f ON p.plane_id = f.plane_id AND f.actual_take_off_time IS NOT NULL AND f.actual_landing_time IS NOT NULL
GROUP BY p.plane_id, a.air_name, p.plane_state
HAVING COUNT(f.code_flight) > 0
ORDER BY p.plane_id;



WITH dispatcher_status AS (
    SELECT e.employee_id,
    e.name AS dispatcher_name,
    e.airport_id,
    a.air_name AS airport_name,
    COUNT(DISTINCT f.plane_id) AS planes_num,
    COUNT(f.code_flight) AS all_accompaniment,
    ROUND(AVG(EXTRACT(EPOCH FROM(f.actual_landing_time - f.actual_take_off_time)) / 3600), 2)  AS avg_accompaniment,
    MAX(f.actual_take_off_time) AS last_take_off
    FROM Employee e
    JOIN Employee_position ep ON e.position_id = ep.position_id
    LEFT JOIN Flight f ON e.employee_id = f.employee_id AND f.actual_take_off_time IS NOT NULL AND f.actual_landing_time IS NOT NULL AND f.actual_take_off_time BETWEEN '2026-01-01' AND '2026-12-31'
    LEFT JOIN Airport a ON e.airport_id = a.airport_id
    WHERE ep.name = 'dispatcher'
    GROUP BY e.employee_id, e.name, e.airport_id, a.air_name
    HAVING COUNT(f.code_flight) > 0
)
SELECT dispatcher_name, airport_name, planes_num, avg_accompaniment, last_take_off, all_accompaniment,
    ROUND(all_accompaniment * 100.0/ AVG(all_accompaniment) OVER (PARTITION BY airport_id), 2) AS  avg_load
    ROUND(AVG(all_accompaniment) OVER (PARTITION BY airport_id ORDER BY all_accompaniment DESC ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING), 2) AS rolling_avg
FROM dispatcher_status
ORDER BY airport_name, all_accompaniment DESC;


WITH strip_actions AS (
    SELECT
        strip_take_off_id AS strip_id,
        actual_take_off_time AS event_time,
        'takeoff' AS event_type
    FROM Flight
    WHERE actual_take_off_time IS NOT NULL

    UNION ALL

    SELECT
        strip_landing_id AS strip_id,
        actual_landing_time AS event_time,
        'landing' AS event_type
    FROM Flight
    WHERE actual_landing_time IS NOT NULL
),
intervals AS (
    SELECT
        strip_id,
        event_time,
        event_type,
        LAG(event_time) OVER (PARTITION BY strip_id ORDER BY event_time) AS prev_time
    FROM strip_actions
)
SELECT
    s.strip_id,
    a.air_name AS airport_name,
    s.status,
    COALESCE(COUNT(i.event_type) FILTER (WHERE i.event_type = 'takeoff'), 0) AS takeoff_count,
    COALESCE(COUNT(i.event_type) FILTER (WHERE i.event_type = 'landing'), 0) AS landing_count,
    COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (i.event_time - i.prev_time)) / 3600), 2), 0) AS avg_occupied_hours,
    COALESCE(ROUND(MAX(EXTRACT(EPOCH FROM (i.event_time - i.prev_time)) / 3600), 2), 0) AS max_occupied_hours,
    MAX(i.event_time) AS last_usage_time
FROM Strip s
LEFT JOIN intervals i ON s.strip_id = i.strip_id
LEFT JOIN Airport a ON s.airport_id = a.airport_id
GROUP BY s.strip_id, a.air_name, s.status
ORDER BY s.strip_id;


SELECT f.code_flight AS flight_id,
    f.planed_take_off_time AS planned_departure,
    f.actual_take_off_time AS actual_departure,
    f.planed_landing_time AS planned_arrival,
    f.actual_landing_time AS actual_arrival,
    ROUND(EXTRACT(EPOCH FROM (f.actual_take_off_time - f.planed_take_off_time)) / 60, 2) AS departure_deviation,
    ROUND(EXTRACT(EPOCH FROM (f.actual_landing_time - f.planed_landing_time)) / 60, 2) AS arrival_deviation,
    dep.air_name AS department_airport,
    arr.air_name AS arrival_airport,
    CASE
        WHEN f.actual_take_off_time IS NULL AND f.actual_landing_time IS NULL THEN 'cancelled'
        WHEN f.actual_take_off_time IS NOT NULL AND f.actual_landing_time IS NULL THEN 'in_flight'
        WHEN f.actual_take_off_time IS NOT NULL AND f.actual_landing_time IS NOT NULL THEN 'completed'
        ELSE 'scheduled'
    END AS flight_status
FROM Flight f
LEFT JOIN Airport dep ON f.take_off_airport_id = dep.airport_id
LEFT JOIN Airport arr ON f.landing_airport_id = arr.airport_id
ORDER BY f.code_flight;

WITH all_mechanics AS (
    SELECT e.employee_id, e.name AS mechanic_name
    FROM Employee e
    JOIN Employee_position ep ON e.position_id = ep.position_id
    WHERE ep.name = 'mechanic'
),
mechanic_checks AS (
    SELECT e.employee_id, e.name AS mechanic_name,
        mc.check_id, mc.checking_start, mc.checking_end,
        sl.status AS new_status,
        EXTRACT(EPOCH FROM (mc.checking_end - mc.checking_start)) / 3600 AS duration_hours
    FROM Mechanical_check mc
    JOIN Status_log sl ON mc.note_id = sl.note_id
    JOIN Employee e ON sl.employee_id = e.employee_id
    JOIN Employee_position ep ON e.position_id = ep.position_id
    WHERE ep.name = 'mechanic'
)
SELECT
    am.employee_id,
    am.mechanic_name,
    COUNT(mc.check_id) AS total_checks,
    COUNT(mc.check_id) FILTER (WHERE mc.new_status = 'ready for take off') AS repaired_aircraft,
    COUNT(mc.check_id) FILTER (WHERE mc.new_status IN ('malfunctioning', 'under mechanic inspection')) AS faulty_aircraft,
    ROUND(COUNT(mc.check_id) FILTER (WHERE mc.new_status = 'malfunctioning') * 100.0 / NULLIF(COUNT(mc.check_id), 0),2) AS critical_fault_percent,
    ROUND(AVG(mc.duration_hours), 2) AS avg_check_hours,
    MAX(mc.checking_end) AS last_check_date
FROM all_mechanics am
LEFT JOIN mechanic_checks mc ON am.employee_id = mc.employee_id
GROUP BY am.employee_id, am.mechanic_name
ORDER BY total_checks DESC;