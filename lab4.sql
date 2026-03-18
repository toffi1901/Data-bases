DROP TABLE IF EXISTS Passenger CASCADE;
DROP TABLE IF EXISTS Flight_ticket CASCADE;
DROP TABLE IF EXISTS Strip_log CASCADE;
DROP TABLE IF EXISTS Position_duty CASCADE;
DROP TABLE IF EXISTS Duty CASCADE;
DROP TABLE IF EXISTS Employee_position CASCADE;
DROP TABLE IF EXISTS Mechanical_check CASCADE;
DROP TABLE IF EXISTS Flight CASCADE;
DROP TABLE IF EXISTS Hangar CASCADE;
DROP TABLE IF EXISTS Plane_position CASCADE;
DROP TABLE IF EXISTS Status_log CASCADE;
DROP TABLE IF EXISTS Plane CASCADE;
DROP TABLE IF EXISTS Employee CASCADE;
DROP TABLE IF EXISTS Strip CASCADE;
DROP TABLE IF EXISTS Airport CASCADE;

DROP TYPE IF EXISTS coord CASCADE;
DROP TYPE IF EXISTS strip_status_enum CASCADE;
DROP TYPE IF EXISTS plane_status_enum CASCADE;
DROP TYPE IF EXISTS name_of_employee_position CASCADE;
DROP TYPE IF EXISTS duty_code_enum CASCADE;


CREATE TYPE coord AS (
    latitude double precision,
    longitude double precision
);

CREATE TYPE strip_status_enum AS ENUM ('free', 'busy');

CREATE TYPE plane_status_enum AS ENUM ('in flight', 'ready for take off', 'malfunctioning', 'under mechanic inspection', 'ready for mechanic inspection');

CREATE TYPE name_of_employee_position AS ENUM ('pilot', 'mechanic', 'dispatcher');

CREATE TYPE duty_code_enum AS ENUM ('D001', 'D002', 'D003', 'D004'); 

CREATE TABLE Airport (
    airport_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    air_name text NOT NULL,
    coordinates coord NOT NULL,
    altitude int NOT NULL,
    radius int NOT NULL,
    city text NOT NULL,
    country text NOT NULL
);

CREATE TABLE Plane (
    plane_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    coordinates coord NOT NULL,
    altitude int,
    width int NOT NULL,
    plane_length int NOT NULL,
    height int NOT NULL,
    plane_state plane_status_enum NOT NULL
);


CREATE TABLE Employee_position (
    position_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name name_of_employee_position NOT NULL UNIQUE
);

CREATE TABLE Duty (
    code duty_code_enum PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE Position_duty (
    position_id int NOT NULL REFERENCES Employee_position(position_id) ON DELETE CASCADE,
    duty_code duty_code_enum NOT NULL REFERENCES Duty(code) ON DELETE CASCADE,
    PRIMARY KEY (position_id, duty_code)
);


CREATE TABLE Strip (
    strip_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    airport_id bigint NOT NULL REFERENCES Airport(airport_id),
    coordinates coord NOT NULL,
    status strip_status_enum NOT NULL
);

CREATE TABLE Employee (
    employee_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name text NOT NULL,
    airport_id bigint REFERENCES Airport(airport_id),
    age int,
    getting_started date,
    position_id int REFERENCES Employee_position(position_id)
);


CREATE TABLE Status_log (
    note_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    plane_id bigint REFERENCES Plane(plane_id),
    employee_id bigint REFERENCES Employee(employee_id),
    change_time timestamptz NOT NULL DEFAULT now(),
    status plane_status_enum NOT NULL
);

CREATE TABLE Plane_position (
    ttime timestamptz NOT NULL,
    coordinates coord NOT NULL,
    PRIMARY KEY(ttime, coordinates),
    plane_id bigint NOT NULL REFERENCES Plane(plane_id),
    direction int NOT NULL,
    pitch int NOT NULL,
    speed int NOT NULL
);


CREATE TABLE Hangar(
    hangar_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY, 
    airport_id bigint NOT NULL REFERENCES Airport(airport_id),
    height int,
    width int,
    hangar_length int,
    coordinates coord NOT NULL
);

CREATE TABLE Flight(
    code_flight bigint NOT NULL PRIMARY KEY,
    plane_id bigint REFERENCES Plane(plane_id),
    employee_id bigint NOT NULL REFERENCES Employee(employee_id),
    strip_take_off_id bigint REFERENCES Strip(strip_id),
    strip_landing_id bigint REFERENCES Strip(strip_id),
    take_off_airport_id bigint REFERENCES Airport(airport_id),
    landing_airport_id bigint REFERENCES Airport(airport_id),
    take_off_time timestamptz,
    landing_time timestamptz,
    planed_take_off_time timestamptz,
    planed_landing_time timestamptz,
    actual_take_off_time timestamptz,
    actual_landing_time timestamptz
);

CREATE TABLE Mechanical_check(
    check_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plane_id bigint NOT NULL REFERENCES Plane(plane_id),
    note_id bigint NOT NULL REFERENCES Status_log(note_id),
    checking_start timestamptz NOT NULL,
    checking_end timestamptz NOT NULL
);


CREATE TABLE Flight_ticket(
    ticket_code bigint PRIMARY KEY,
    code_flight bigint REFERENCES Flight(code_flight)
);

CREATE TABLE Passenger (
    passenger_id bigint NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    ticket_code bigint REFERENCES Flight_ticket(ticket_code),
    passenger_name text NOT NULL,
    age int,
    passport bigint UNIQUE NOT NULL,
    citizenship_country text NOT NULL,
    time_issuance date NOT NULL,
    department_code text NOT NULL,
    issued_by text NOT NULL
);


CREATE TABLE Strip_log (
    note_number int NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    plane_id bigint REFERENCES Plane(plane_id),
    strip_id bigint REFERENCES Strip(strip_id),
    airport_id bigint REFERENCES Airport(airport_id),
    planes_number int,
    destination_time timestamptz,
    let_go_time timestamptz
);
