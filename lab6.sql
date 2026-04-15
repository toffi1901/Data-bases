DROP TRIGGER IF EXISTS trg_plane_status ON Plane;
DROP TRIGGER IF EXISTS tr_strip_status ON Strip;

DROP FUNCTION IF EXISTS find_distance(double precision, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS change_plane_status();
DROP FUNCTION IF EXISTS change_strip_status();
DROP FUNCTION IF EXISTS prevent_strip_update();

create or replace function find_distance(lat1 double precision, lat2 double precision, lon1 double precision, lon2 double precision)
returns double precision as $$
declare
    R double precision := 6371;
    lat double precision;
    lon double precision;

begin
    lat := radians(lat2 - lat1);
    lon := radians(lon2 - lon1);
    return 2 * R * asin(sqrt(power(sin(lat/2), 2) + cos(radians(lat1))*cos(radians(lat2)) * power(sin(lon/2), 2)));
end;
$$ LANGUAGE plpgsql IMMUTABLE;

create or replace function change_plane_status()
returns trigger
LANGUAGE plpgsql
as $$
declare current_flight record; 
        dist double precision; 
        dest_lat double precision;
        dest_lon double precision;
begin
    if NEW.coordinates is distinct from OLD.coordinates then
        select code_flight, landing_airport_id into current_flight
        from Flight
        where plane_id = NEW.plane_id and landing_airport_id is not null
        order by planed_landing_time
        limit 1;
        if found then
            select (coordinates).latitude, (coordinates).longitude  into dest_lat, dest_lon
            from Airport
            where airport_id = current_flight.landing_airport_id;
            dist := find_distance((NEW.coordinates).latitude, dest_lat, 
                                      (NEW.coordinates).longitude, dest_lon);
            if dist < 20 and NEW.plane_state != 'ready for mechanic inspection' then
                NEW.plane_state := 'ready for mechanic inspection';
                insert into Status_log(plane_id, employee_id, change_time, status)
                values (NEW.plane_id, NULL, now(), 'ready for mechanic inspection');
            end if;
        end if;
    end if;
    return NEW;
end;
$$;

create trigger trg_plane_status
    before update on Plane
    for each row
    execute function change_plane_status();

create or replace function change_strip_status()
returns trigger
LANGUAGE plpgsql
as $$
declare new_strip_id bigint;
        Copy_flight Flight%rowtype;
begin
    if NEW.coordinates is distinct from OLD.coordinates or NEW.altitude is distinct from OLD.altitude then
        select * into Copy_flight 
        from Flight f
        where plane = NEW.plane_id 
        order by planed_take_off_time
        limit 1;

        if found then   
            if NEW.altitude > 100 and NEW.plane_state = 'in flight' and OLD.plane_state != 'in flight' then
                new.strip_id := f.strip_take_off_id;
                if new_strip_id is not null then
                    update Strip set status = 'free'
                    where strip_id = new_strip_id;
                end if;
            elseif NEW.plane_state = 'ready for mechanic inspection' and OLD.plane_state != 'ready for mechanic inspection' then
                new.strip_id := f.strip_landing_id;
                if new_strip_id is not null then
                    update Strip set status = 'free'
                    where strip_id = new_strip_id;
                end if;
            end if;
        end if;
    end if;
    return NEW;
 end;      
$$;

create or replace function prevent_strip_update()
returns trigger 
LANGUAGE plpgsql
as $$
begin  
    if tg_op = 'UPDATE' and OLD.status is distinct from NEW.status then
        raise exception 'оно само, ручками не трогать';
    end if;
    return NEW;
end;
$$;

DROP TRIGGER IF EXISTS tr_strip_status ON Strip;
create trigger tr_strip_status
    before update on Strip  
    for each row
    execute function prevent_strip_update();

create table if not exists Dispatcher_responsibility(
    dispatcher_id bigint not null REFERENCES Employee(employee_id),
    responsibility_id bigint GENERATED ALWAYS as IDENTITY PRIMARY KEY,
    plane_id bigint not null REFERENCES Plane(plane_id),
    airport_id bigint not null REFERENCES Airport(airport_id),
    start_time timestamptz not null DEFAULT now(),
    end_time timestamptz
);

DROP PROCEDURE IF EXISTS add_dispatcher(bigint, bigint);

create procedure add_dispatcher(p_plane_id bigint, p_airport_id bigint)
LANGUAGE plpgsql
as $$
declare new_dispatcher_id bigint;
begin
    select e.employee_id into new_dispatcher_id
    from Employee e
    left join Dispatcher_responsibility dr on dr.dispatcher_id = e.employee_id
    where e.position_id = (select position_id
                            from Employee_position
                            where name = 'dispatcher') and e.airport_id = p_airport_id
    group by e.employee_id
    order by count(dr.responsibility_id)
    limit 1;

    if not found then 
        raise exception 'все заняты(или уволены), увы(((';
    end if;

    insert into Dispatcher_responsibility(dispatcher_id, plane_id, airport_id, start_time) values (new_dispatcher_id, p_plane_id, p_airport_id, now());
    RAISE NOTICE 'Диспетчер % назначен на самолёт % в аэропорту %', new_dispatcher_id, p_plane_id, p_airport_id;
end;
$$;

DROP PROCEDURE IF EXISTS appoint_strip(bigint, plane_status_enum);

create procedure appoint_strip(p_plane_id bigint, p_plane_status plane_status_enum)
LANGUAGE plpgsql
as $$
declare new_strip_id bigint;
        new_plane_status plane_status_enum;
        new_flight_id bigint;
        new_airport_id bigint;
        new_queue_ct bigint;
begin
    select plane_state into new_plane_status
    from Plane p
    where p.plane_id = p_plane_id;
    if p_plane_status = 'ready for take off' and new_plane_status != 'ready for take off' then 
        raise exception 'Plane % not ready for take off, state %', p_plane_id, p_plane_status;
    elseif p_plane_status = 'ready for mechanic inspection' and new_plane_status != 'ready for mechanic inspection' then
        raise exception 'Plane % not ready for landing, state %', p_plane_id, p_plane_status;
    end if;

    if p_plane_status = 'ready for take off' then 
        select code_flight, take_off_airport_id into new_flight_id, new_airport_id
        from Flight f
        where plane_id = p_plane_id and f.actual_take_off_time is null and actual_landing_time is null and take_off_airport_id is not null
        order by f.planed_take_off_time
        limit 1;

        if not found then 
            raise exception 'flight for taking off is not found for plane %', p_plane_id;
        end if;
    else
        select code_flight, take_off_airport_id into new_flight_id, new_airport_id
        from Flight 
        where plane_id = p_plane_id and actual_take_off_time is not null and actual_landing_time is null and landing_airport_id is not null
        order by planed_landing_time
        limit 1;

        if not found then 
            raise exception 'flight for landing is not found for plane %', p_plane_id;
        end if;
    end if;

    select s.strip_id, coalesce(queue.ct, 0) into new_strip_id, new_queue_ct
    from Strip s
    left join lateral (select count(*) as ct
                    from Flight f 
                    where (p_plane_status = 'ready for take off' and f.strip_take_off_id = s.strip_id and f.actual_take_off_time is null) 
                        or (p_plane_status = 'ready for mechanic inspection' and f.strip_landing_id = s.strip_id and f.actual_landing_time is null) 
                    ) queue on true
    where s.airport_id = new_airport_id and s.status = 'free'
    order by queue.ct
    limit 1;

    if not found then
        raise exception 'no strips, all busy';
    end if;

    if p_plane_status = 'ready for take off' then
        update Flight set strip_take_off_id = new_strip_id
        where code_flight = new_flight_id;
    else
        update Flight set strip_landing_id = new_strip_id
        where code_flight = new_flight_id;
    end if;

    insert into Strip_log(plane_id, strip_id, airport_id, destination_time, let_go_time) values (p_plane_id, new_strip_id, new_airport_id, now(), NULL);
end;

$$;