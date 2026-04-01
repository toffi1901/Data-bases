DROP TRIGGER IF EXISTS change_plane_status ON Plane;
DROP TRIGGER IF EXISTS change_strip_status ON Plane;
DROP TRIGGER IF EXISTS prevent_strip_update ON Strip;

DROP FUNCTION IF EXISTS find_distance(double precision, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS change_plane_status();
DROP FUNCTION IF EXISTS change_strip_status();
DROP FUNCTION IF EXISTS prevent_strip_update();

DROP PROCEDURE IF EXISTS add_dispatcher(bigint, bigint);
DROP PROCEDURE IF EXISTS appoint_strip(bigint, action_type_enum);

DROP TYPE IF EXISTS action_type_enum CASCADE;




create or replace function find_distance(lat1 double precision, lat2 double precision, lon1 double precision, lon2 double precision)
returns double precision as $$
declare
    R double precision := 6371;
    lat double precision;
    lon double precision;

begin
    lat := radians(lat2 - lat1);
    lon := radians(lon2 - lon1);
    return 2 * R * sqrt(power(sin(lat/2), 2) + cos(radians(lat1))*cos(radians(lat2)) * power(sin(lon/2), 2));
end;
$$ LANGUAGE plpgsql IMMUTABLE;


create or replace function change_plane_status() 
returns trigger as $$
declare current_flight record;
    coord_dst coord;
    dist double precision;
begin   
    if NEW.coordinates is distinct from OLD.coordinates then 
        select flight_id, landing_airport_id into current_flight
        from Flight
        where plane_id = NEW.plane_id and actual_landing_time is NULL
        order by planed_landing_time 
        limit 1;

        if found then 
            select coordinates into coord_dst
            from Airport
            where airport_id = current_flight.landing_airport_id;
            dist := find_distance((NEW.coordinates).latitude, (coord_dst).latitude, (NEW.coordinates).longitude, (coord_dst).longitude);
            if dist < 20 and NEW.plane_state != 'ready for mechanic inspection' then
                NEW.plane_state := 'ready for mechanic inspection';
                INSERT INTO Status_log (plane_id, employee_id, change_time, status)
                VALUES (NEW.plane_id, NULL, now(), 'ready for mechanic inspection');
            end if;
        end if;
    end if;
    return NEW;
end;
$$ LANGUAGE plpgsql;

create trigger change_plane_status
    before update on Plane
    for each ROW
    execute function change_plane_status();

create or replace function change_strip_status()
returns trigger as $$
declare new_strip_id bigint; flight Flight%rowtype;
begin   
    select * into flight
    from Flight
    where plane_id = NEW.plane_id and actual_landing_time is null
    order by planed_take_off_time
    limit 1;

        if found then 
            return NEW;
        end if; 
        if NEW.altitude >= 100 and NEW.plane_state != 'in flight' and OLD.plane_state != 'in flight' then
            new_strip_id := flight.strip_take_off_id;
            if new_strip_id is not null then
                update Strip set status = 'free'
                where strip_id = new_strip_id;
            end if;

        elsif NEW.plane_state = 'ready for mechanic inspection' and OLD.plane_state != 'ready for mechanic inspection' then
            new_strip_id := flight.strip_landing_id;
            if new_strip_id is not null then
                update Strip set status = 'free'
                where strip_id = new_strip_id;
            end if;
        end if;

    return NEW;
end;
$$ LANGUAGE plpgsql;

create trigger change_strip_status
    before update on Plane
    for each ROW
    execute function change_strip_status();

create or replace function prevent_strip_update()
returns trigger as $$
begin  
    if tg_op = 'update' and OLD.status is distinct from NEW.status then
        raise exception 'оно само, ручками не трогать';
    end if;
    return NEW;
end;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_strip_update
    BEFORE UPDATE ON Strip
    FOR EACH ROW
    EXECUTE FUNCTION prevent_strip_update();


create table if not exists Dispatcher_responsibility(
    dispatcher_id bigint not null REFERENCES Employee(employee_id),
    responsibility_id bigint GENERATED ALWAYS as IDENTITY PRIMARY KEY,
    plane_id bigint not null REFERENCES Plane(plane_id),
    airport_id bigint not null REFERENCES Airport(airport_id),
    start_time timestamptz not null DEFAULT now(),
    end_time timestamptz
);


create procedure add_dispatcher(plane_id bigint, airport_id bigint)
LANGUAGE plpgsql
as $$
declare new_dispatcher_id bigint;
begin 
    select e.employee_id
    into new_dispatcher_id
    from Employee e
    left join Dispatcher_responsibility dr on dr.dispatcher_id = e.employee_id and dr.end_time is null 
    where e.position_id = (select position_id 
                            from Employee_position 
                            where position_id = 'dispatcher') and e.airport_id = airport_id
    group by e.employee_id
    order by count(dr.responsibility_id)
    limit 1;

    if not found then 
        raise exception 'все заняты(или уволены), увы(((';
    end if;

    insert into Dispatcher_responsibility(dispatcher_id, plane_id, airport_id, start_time) values (dispatcher_id, plane_id, airport_id, now());
    RAISE NOTICE 'Диспетчер % назначен на самолёт % в аэропорту %', new_dispatcher_id, plane_id, airport_id;
end;
$$;


CREATE TYPE action_type_enum AS ENUM ('taking off', 'landing');


create procedure appoint_strip(tmp_plane_id bigint, action_type action_type_enum)
LANGUAGE plpgsql
as $$
declare tmp_strip_id bigint;
    tmp_plane_state plane_status_enum;
    tmp_flight_id bigint;
    tmp_airport_id bigint;
    tmp_queue_ct bigint;
begin 
    select plane_state into tmp_plane_state 
    from Plane
    where plane_id = tmp_plane_id;
    if action_type = 'taking off' and tmp_plane_state != 'ready for take off' then
        RAISE EXCEPTION 'Plane % not ready for take off, state %', tmp_plane_id, tmp_plane_state;
    elsif action_type = 'landing' and tmp_plane_state != 'ready for mechanic inspection' then
        RAISE EXCEPTION 'Plane % not ready for landing, state %',  tmp_plane_id, tmp_plane_state;
    end if;

    if action_type = 'taking off' then 
        select code_flight, take_off_airport_id into tmp_flight_id, tmp_airport_id
        from Flight
        where plane_id = tmp_plane_id and actual_take_off_time is null and actual_landing_time is null and take_off_airport_id is not null
        order by planed_take_off_time
        limit 1;

        if not found then 
            raise exception 'flight for taking off is not found for plane %', tmp_plane_id;
        end if;
    else
        select code_flight, take_off_airport_id into tmp_flight_id, tmp_airport_id
        from Flight
        where plane_id = tmp_plane_id and actual_landing_time is null and landing_airport_id is not null
        order by planed_landing_time
        limit 1;

        if not found then 
            raise exception 'flight for landing is not found for plane %', tmp_plane_id;
        end if;
    end if;

    select s.strip_id, coalesce(queue.ct, 0) into tmp_strip_id, tmp_queue_ct
    from Strip s
    left join lateral (
        select count(*) as ct 
        from Flight f 
        where (action_type = 'taking off' and f.strip_take_off_id = s.strip_id and f.actual_take_off_time is null) or (action_type = 'landing' and f.strip_landing_id = s.strip_id and f.actual_landing_time is null) 
    ) queue on true
    where s.airport_id = tmp_airport_id and s.status = 'free'
    order by queue.ct 
    limit 1;

    if not found then
        raise exception 'no strips, all busy';
    end if;

    if action_type = 'taking off' then
        update Flight set strip_take_off_id = tmp_strip_id
        where code_flight = tmp_flight_id;
    else
        update Flight set strip_landing_id = tmp_strip_id
        where code_flight = tmp_flight_id;
    end if;

    insert into Strip_log(plane_id, strip_id, airport_id, destination_time, let_go_time) values (tmp_plane_id, tmp_strip_id, tmp_airport_id, now(), NULL);
end;
$$;

