BEGIN;

INSERT INTO Airport (air_name, coordinates, altitude, radius, city, country) VALUES
    ('Domodedovo', ROW(55.4086, 37.9063)::coord, 500, 10, 'Moscow', 'Russia'),
    ('Sheremetyevo', ROW(55.9726, 37.4146)::coord, 600, 12, 'Moscow', 'Russia');

INSERT INTO Employee_position (name) VALUES
    ('pilot'), ('mechanic'), ('dispatcher');

INSERT INTO Duty (code, name) VALUES
    ('D001'::duty_code_enum, 'Flight coordination'),
    ('D002'::duty_code_enum, 'Maintenance');

INSERT INTO Position_duty (position_id, duty_code)
SELECT position_id, 'D001'::duty_code_enum FROM Employee_position WHERE name = 'dispatcher'
UNION ALL
SELECT position_id, 'D002'::duty_code_enum FROM Employee_position WHERE name = 'mechanic';

INSERT INTO Employee (name, airport_id, age, getting_started, position_id) VALUES
    ('Ivan Dispatcher',  (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'), 35, '2020-01-01', (SELECT position_id FROM Employee_position WHERE name = 'dispatcher')),
    ('Petr Dispatcher',  (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'), 40, '2019-05-15', (SELECT position_id FROM Employee_position WHERE name = 'dispatcher')),
    ('Pilot Test',       (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'), 45, '2010-01-01', (SELECT position_id FROM Employee_position WHERE name = 'pilot'));

INSERT INTO Strip (airport_id, coordinates, status) VALUES
    ((SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'),   ROW(55.4087, 37.9064)::coord, 'free'),
    ((SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'),   ROW(55.4088, 37.9065)::coord, 'free'),
    ((SELECT airport_id FROM Airport WHERE air_name = 'Sheremetyevo'), ROW(55.9727, 37.4147)::coord, 'free'),
    ((SELECT airport_id FROM Airport WHERE air_name = 'Sheremetyevo'), ROW(55.9728, 37.4148)::coord, 'free');

--Plane A для триггера(хррррррр)
INSERT INTO Plane (coordinates, altitude, width, plane_length, height, plane_state) VALUES
    (ROW(55.4086, 37.9063)::coord, 0, 10, 30, 8, 'ready for take off');
-- Самолёт B (для теста appoint_strip, останется в ready for take off)
INSERT INTO Plane (coordinates, altitude, width, plane_length, height, plane_state) VALUES
    (ROW(55.4086, 37.9063)::coord, 0, 10, 30, 8, 'ready for take off');

UPDATE Plane p SET base_airport_id = (
    SELECT airport_id FROM Airport a
    ORDER BY ((p.coordinates).latitude - (a.coordinates).latitude)^2 +
             ((p.coordinates).longitude - (a.coordinates).longitude)^2
    LIMIT 1
);

DO $$
DECLARE
    v_pilot_id bigint;
    v_dep_id bigint;
    v_dest_id bigint;
    v_planeA_id bigint;
    v_planeB_id bigint;
BEGIN
    SELECT employee_id INTO v_pilot_id FROM Employee WHERE name = 'Pilot Test' LIMIT 1;
    SELECT airport_id INTO v_dep_id FROM Airport WHERE air_name = 'Domodedovo';
    SELECT airport_id INTO v_dest_id FROM Airport WHERE air_name = 'Sheremetyevo';
    SELECT plane_id INTO v_planeA_id FROM Plane WHERE plane_id = (SELECT plane_id FROM Plane LIMIT 1 OFFSET 0);
    SELECT plane_id INTO v_planeB_id FROM Plane WHERE plane_id = (SELECT plane_id FROM Plane LIMIT 1 OFFSET 1);
    
    -- Рейс для самолёта A (взлёт из Domodedovo, посадка в Sheremetyevo)
    INSERT INTO Flight (code_flight, plane_id, employee_id, strip_take_off_id, strip_landing_id,
                        take_off_airport_id, landing_airport_id,
                        planed_take_off_time, planed_landing_time)
    VALUES (1001, v_planeA_id, v_pilot_id, NULL, NULL, v_dep_id, v_dest_id,
            now() + interval '1 hour', now() + interval '3 hours');
    -- Рейс для самолёта B (аналогичный)
    INSERT INTO Flight (code_flight, plane_id, employee_id, strip_take_off_id, strip_landing_id,
                        take_off_airport_id, landing_airport_id,
                        planed_take_off_time, planed_landing_time)
    VALUES (1002, v_planeB_id, v_pilot_id, NULL, NULL, v_dep_id, v_dest_id,
            now() + interval '2 hours', now() + interval '4 hours');
END $$;

--  ТЕСТ 1: trg_plane_status (меняем состояние самолёта A) 
SELECT ' TEST 1: trg_plane_status (plane A)' AS test;

DO $$
DECLARE
    v_plane_id bigint;
    v_plane_state text;
    v_log_record record;
BEGIN
    SELECT plane_id INTO v_plane_id FROM Plane LIMIT 1 OFFSET 0;
    
    -- до обновления
    SELECT plane_state INTO v_plane_state FROM Plane WHERE plane_id = v_plane_id;
    RAISE NOTICE 'До обновления: plane_id=%, state=%', v_plane_id, v_plane_state;
    
    UPDATE Plane
    SET coordinates = ROW(55.96, 37.40)::coord
    WHERE plane_id = v_plane_id;
    
    -- смотрим на апдейт
    SELECT plane_state INTO v_plane_state FROM Plane WHERE plane_id = v_plane_id;
    RAISE NOTICE 'После обновления: plane_id=%, state=%', v_plane_id, v_plane_state;
    
    FOR v_log_record IN SELECT * FROM Status_log WHERE plane_id = v_plane_id LOOP
        RAISE NOTICE 'Лог: %', v_log_record;
    END LOOP;
END $$;

-- (запрещаем шаманить лапками)
SELECT 'TEST 2: tr_strip_status ' AS test;
DO $$
DECLARE
    sid bigint;
BEGIN
    SELECT strip_id INTO sid FROM Strip WHERE airport_id = (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo') LIMIT 1;
    UPDATE Strip SET status = 'busy' WHERE strip_id = sid;
    RAISE EXCEPTION 'Триггер не сработал';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Ожидаемое исключение: %', SQLERRM;
END $$;
SELECT strip_id, status FROM Strip WHERE airport_id = (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo') LIMIT 1;

SELECT ' TEST 3: add_dispatcher' AS test;
SELECT * FROM Dispatcher_responsibility;
DO $$
DECLARE
    v_plane_id bigint;
    v_airport_id bigint;
BEGIN
    SELECT plane_id INTO v_plane_id FROM Plane LIMIT 1 OFFSET 0;  -- берём самолёт A
    SELECT airport_id INTO v_airport_id FROM Airport WHERE air_name = 'Domodedovo';
    CALL add_dispatcher(v_plane_id, v_airport_id);
END $$;
SELECT * FROM Dispatcher_responsibility;

ROLLBACK;

BEGIN;

INSERT INTO Airport (air_name, coordinates, altitude, radius, city, country) VALUES
    ('Domodedovo', ROW(55.4086, 37.9063)::coord, 500, 10, 'Moscow', 'Russia'),
    ('Sheremetyevo', ROW(55.9726, 37.4146)::coord, 600, 12, 'Moscow', 'Russia');


INSERT INTO Employee_position (name) VALUES ('pilot'), ('dispatcher');

INSERT INTO Employee (name, airport_id, age, getting_started, position_id) VALUES
    ('Pilot Test', (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'), 45, '2010-01-01',
     (SELECT position_id FROM Employee_position WHERE name = 'pilot'));

INSERT INTO Strip (airport_id, coordinates, status) VALUES
    ((SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'), ROW(55.4087, 37.9064)::coord, 'free');

INSERT INTO Plane (coordinates, altitude, width, plane_length, height, plane_state) VALUES
    (ROW(55.4086, 37.9063)::coord, 0, 10, 30, 8, 'ready for take off');

-- Рейс без  полосы
INSERT INTO Flight (code_flight, plane_id, employee_id, take_off_airport_id, landing_airport_id,
                    planed_take_off_time, planed_landing_time)
VALUES (1001,
        (SELECT plane_id FROM Plane LIMIT 1),
        (SELECT employee_id FROM Employee WHERE name = 'Pilot Test'),
        (SELECT airport_id FROM Airport WHERE air_name = 'Domodedovo'),
        (SELECT airport_id FROM Airport WHERE air_name = 'Sheremetyevo'),
        now() + interval '1 hour', now() + interval '3 hours');

DO $$
DECLARE
    v_plane_id bigint;
BEGIN
    SELECT plane_id INTO v_plane_id FROM Plane LIMIT 1;
    CALL appoint_strip(v_plane_id, 'ready for take off'::plane_status_enum);
END $$;

SELECT code_flight, strip_take_off_id FROM Flight WHERE code_flight = 1001;
SELECT * FROM Strip_log;



ROLLBACK;
