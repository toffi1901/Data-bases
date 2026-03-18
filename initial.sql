INSERT INTO Employee_position (name) VALUES
    ('pilot'),
    ('mechanic'),
    ('dispatcher');

INSERT INTO Duty (code, name) VALUES
    ('D001', 'Пилотирование'),
    ('D002', 'Техническое обслуживание'),
    ('D003', 'Диспетчерское управление'),
    ('D004', 'Планирование полётов');

INSERT INTO Position_duty (position_id, duty_code) VALUES
    ((SELECT position_id FROM Employee_position WHERE name = 'pilot'), 'D001'),
    ((SELECT position_id FROM Employee_position WHERE name = 'mechanic'), 'D002'),
    ((SELECT position_id FROM Employee_position WHERE name = 'dispatcher'), 'D003'),
    ((SELECT position_id FROM Employee_position WHERE name = 'dispatcher'), 'D004');

INSERT INTO Airport (air_name, coordinates, altitude, radius, city, country) VALUES
    ('Шереметьево', ROW(55.972642, 37.414589)::coord, 190, 50, 'Москва', 'Россия'),
    ('Домодедово', ROW(55.408786, 37.906314)::coord, 179, 50, 'Москва', 'Россия'),
    ('Пулково', ROW(59.800292, 30.262503)::coord, 24, 40, 'Санкт-Петербург', 'Россия');

INSERT INTO Strip (airport_id, coordinates, status) VALUES
    (1, ROW(55.972642, 37.414589)::coord, 'free'),
    (1, ROW(55.973000, 37.415000)::coord, 'busy'),
    (2, ROW(55.408786, 37.906314)::coord, 'free'),
    (2, ROW(55.409000, 37.907000)::coord, 'free'),
    (3, ROW(59.800292, 30.262503)::coord, 'busy'),
    (3, ROW(59.801000, 30.263000)::coord, 'free');

INSERT INTO Employee (name, airport_id, age, getting_started, position_id) VALUES
    ('Иван Петров', 1, 35, '2015-06-01', (SELECT position_id FROM Employee_position WHERE name = 'pilot')),
    ('Мария Иванова', 1, 29, '2018-09-15', (SELECT position_id FROM Employee_position WHERE name = 'dispatcher')),
    ('Пётр Сидоров', 2, 42, '2010-03-20', (SELECT position_id FROM Employee_position WHERE name = 'mechanic'));

INSERT INTO Plane (coordinates, altitude, width, plane_length, height, plane_state) VALUES
    (ROW(55.972642, 37.414589)::coord, 0, 4, 40, 12, 'ready for take off'),
    (ROW(55.408786, 37.906314)::coord, 10000, 5, 45, 13, 'in flight'),
    (ROW(59.800292, 30.262503)::coord, 500, 3, 30, 10, 'under mechanic inspection');

INSERT INTO Status_log (plane_id, employee_id, change_time, status) VALUES
    (1, 1, now(), 'ready for take off'),
    (2, 2, now() - interval '2 hours', 'in flight'),
    (3, 3, now() - interval '1 day', 'under mechanic inspection');

INSERT INTO Plane_position (ttime, coordinates, plane_id, direction, pitch, speed) VALUES
    (now() - interval '30 minutes', ROW(55.980000, 37.420000)::coord, 2, 45, 5, 850),
    (now() - interval '20 minutes', ROW(56.000000, 37.500000)::coord, 2, 45, 5, 860),
    (now() - interval '10 minutes', ROW(56.020000, 37.600000)::coord, 2, 45, 5, 870);

INSERT INTO Flight (code_flight, plane_id, employee_id, strip_take_off_id, strip_landing_id,
                    take_off_airport_id, landing_airport_id,
                    take_off_time, landing_time,
                    planed_take_off_time, planed_landing_time,
                    actual_take_off_time, actual_landing_time) VALUES
    (101, 2, 2, 3, 5,
     2, 3,
     now() - interval '2 hours', now() - interval '1 hour',
     now() - interval '2 hours 5 minutes', now() - interval '1 hour 5 minutes',
     now() - interval '2 hours', now() - interval '1 hour 2 minutes');

INSERT INTO Flight_ticket (ticket_code, code_flight) VALUES
    (1001, 101),
    (1002, 101),
    (1003, 101);

INSERT INTO Passenger (ticket_code, passenger_name, age, passport, citizenship_country,
                       time_issuance, department_code, issued_by) VALUES
    (1001, 'Алексей Смирнов', 30, 1234567890, 'Россия', '2015-07-20', '770-001', 'ОВД Тверской'),
    (1002, 'Елена Кузнецова', 25, 1234567891, 'Россия', '2018-03-12', '770-002', 'ОВД Арбат'),
    (1003, 'Дмитрий Иванов', 40, 1234567892, 'Россия', '2010-11-05', '770-003', 'ОВД Хамовники');

INSERT INTO Strip_log (plane_id, strip_id, airport_id, planes_number, destination_time, let_go_time)
SELECT 2, 3, airport_id, 1, now() - interval '2 hours 5 minutes', now() - interval '2 hours'
FROM Strip WHERE strip_id = 3;
INSERT INTO Strip_log (plane_id, strip_id, airport_id, planes_number, destination_time, let_go_time)
SELECT 2, 5, airport_id, 1, now() - interval '1 hour 5 minutes', now() - interval '1 hour 2 minutes'
FROM Strip WHERE strip_id = 5;