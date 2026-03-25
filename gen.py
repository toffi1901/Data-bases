import psycopg2
from faker import Faker
import logging
import random
from datetime import datetime, timedelta
from psycopg2.extras import execute_values

class DataBaseFiller:

    def __init__(self, db_config, num_airports=3, num_planes=10, num_strips_per_airport=2,
                 num_employees=15, num_status_logs_per_plane=3, num_positions_per_plane=5,
                 num_hangars_per_airport=2, num_flights=20, num_mechanical_checks=5,
                 num_tickets_per_flight=20, num_passengers=40, num_strip_logs=25):
        self.fake = Faker('ru_RU')
        self.db_config = db_config
        self.conn = None
        self.cursor = None

        self.num_airports = num_airports
        self.num_planes = num_planes
        self.num_strips_per_airport = num_strips_per_airport
        self.num_employees = num_employees
        self.num_status_logs_per_plane = num_status_logs_per_plane
        self.num_positions_per_plane = num_positions_per_plane
        self.num_hangars_per_airport = num_hangars_per_airport
        self.num_flights = num_flights
        self.num_mechanical_checks = num_mechanical_checks
        self.num_tickets_per_flight = num_tickets_per_flight
        self.num_passengers = num_passengers
        self.num_strip_logs = num_strip_logs

        self.airport_ids = []
        self.plane_ids = []
        self.strip_ids = []
        self.employee_ids = []
        self.flight_ids = []
        self.ticket_codes = []
        self.note_ids = []

        self.strip_statuses = ['free', 'busy']
        self.plane_statuses = [
            'in flight', 'ready for take off', 'malfunctioning',
            'under mechanic inspection', 'ready for mechanic inspection'
        ]
        self.employee_positions = ['pilot', 'mechanic', 'dispatcher']
        self.duty_codes = ['D001', 'D002', 'D003', 'D004']
        self.duty_names = ['Пилотирование', 'Техническое обслуживание', 'Диспетчерское управление', 'Планирование полётов']

    def connect(self):
        try:
            self.conn = psycopg2.connect(**self.db_config)
            self.cursor = self.conn.cursor()
            logging.info("Successful connection to DB")
        except Exception as e:
            logging.error(f"Error connection: {e}")
            raise

    def close(self):
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
        logging.info("Connection was closed")

    def random_coord(self):
        lat = round(random.uniform(40.0, 70.0), 6)
        lon = round(random.uniform(30.0, 180.0), 6)
        return lat, lon

    def fill_employee_position_duty(self):
        for pos in self.employee_positions:
            self.cursor.execute(
                "INSERT INTO Employee_position (name) VALUES (%s) ON CONFLICT DO NOTHING",
                (pos,)
            )

        self.cursor.execute("SELECT position_id, name FROM Employee_position")
        pos_map = {name: pid for pid, name in self.cursor.fetchall()}

        for code, name in zip(self.duty_codes, self.duty_names):
            self.cursor.execute(
                "INSERT INTO Duty (code, name) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (code, name)
            )

        pos_duty = [
            ('pilot', 'D001'),
            ('pilot', 'D003'),
            ('mechanic', 'D002'),
            ('dispatcher', 'D001'),
            ('dispatcher', 'D004')
        ]
        for pos_name, duty_code in pos_duty:
            pos_id = pos_map.get(pos_name)
            if pos_id:
                self.cursor.execute(
                    "INSERT INTO Position_duty (position_id, duty_code) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    (pos_id, duty_code)
                )
        self.conn.commit()
        logging.info("Employee_position, Duty, Position_duty filled")

    def fill_airport(self):
        for _ in range(self.num_airports):
            name = f"{self.fake.city()} Airport"
            lat, lon = self.random_coord()
            altitude = random.randint(50, 500)
            radius = random.randint(1000, 5000)
            city = self.fake.city()
            country = "Russia"
            self.cursor.execute(
                "INSERT INTO Airport (air_name, coordinates, altitude, radius, city, country) "
                "VALUES (%s, ROW(%s,%s)::coord, %s, %s, %s, %s) RETURNING airport_id",
                (name, lat, lon, altitude, radius, city, country)
            )
            airport_id = self.cursor.fetchone()[0]
            self.airport_ids.append(airport_id)
        self.conn.commit()
        logging.info(f"{len(self.airport_ids)} airports added")

    def fill_strip(self):
        for airport_id in self.airport_ids:
            num_strips = random.randint(1, self.num_strips_per_airport)
            for _ in range(num_strips):
                lat, lon = self.random_coord()
                status = random.choice(self.strip_statuses)
                self.cursor.execute(
                    "INSERT INTO Strip (airport_id, coordinates, status) "
                    "VALUES (%s, ROW(%s,%s)::coord, %s) RETURNING strip_id",
                    (airport_id, lat, lon, status)
                )
                strip_id = self.cursor.fetchone()[0]
                self.strip_ids.append(strip_id)
        self.conn.commit()
        logging.info(f"{len(self.strip_ids)} strips added")

    def fill_plane(self):
        for _ in range(self.num_planes):
            lat, lon = self.random_coord()
            altitude = random.randint(0, 12000)
            width = random.randint(9, 88)
            plane_length = random.randint(7, 85)
            height = random.randint(2, 20)
            plane_state = random.choice(self.plane_statuses)
            base_airport_id = random.choice(self.airport_ids) if self.airport_ids else None
            self.cursor.execute("""INSERT INTO Plane (coordinates, altitude, width, plane_length, height, plane_state, base_airport_id)
                VALUES (ROW(%s, %s)::coord, %s, %s, %s, %s, %s, %s) plane_id""",
                (lat, lon, altitude, width, plane_length, height, plane_state, base_airport_id)
            )
            plane_id = self.cursor.fetchone()[0]
            self.plane_ids.append(plane_id)
        self.conn.commit()
        logging.info(f"{len(self.plane_ids)} planes added")

    def fill_employee(self):
        self.cursor.execute("SELECT position_id FROM Employee_position")
        position_ids = [row[0] for row in self.cursor.fetchall()]

        for _ in range(self.num_employees):
            name = self.fake.name()
            airport_id = random.choice(self.airport_ids) if self.airport_ids else None
            age = random.randint(20, 65)
            getting_started = self.fake.date_between(start_date='-10y', end_date='today')
            position_id = random.choice(position_ids)
            self.cursor.execute(
                "INSERT INTO Employee (name, airport_id, age, getting_started, position_id) "
                "VALUES (%s, %s, %s, %s, %s) RETURNING employee_id",
                (name, airport_id, age, getting_started, position_id)
            )
            emp_id = self.cursor.fetchone()[0]
            self.employee_ids.append(emp_id)
        self.conn.commit()
        logging.info(f"{len(self.employee_ids)} employees added")

    def fill_status_log(self):
        if not self.employee_ids:
            logging.warning("No employees for Status_log")
            return

        for plane_id in self.plane_ids:
            num_logs = random.randint(1, self.num_status_logs_per_plane)
            for _ in range(num_logs):
                change_time = self.fake.date_time_between(start_date='-30d', end_date='now')
                status = random.choice(self.plane_statuses)
                employee_id = random.choice(self.employee_ids)
                self.cursor.execute(
                    "INSERT INTO Status_log (plane_id, employee_id, change_time, status) "
                    "VALUES (%s, %s, %s, %s) RETURNING note_id",
                    (plane_id, employee_id, change_time, status)
                )
                note_id = self.cursor.fetchone()[0]
                self.note_ids.append(note_id)
        self.conn.commit()
        logging.info(f"{len(self.note_ids)} status logs added")

    def fill_hangar(self):
        for airport_id in self.airport_ids:
            num_hangars = random.randint(1, self.num_hangars_per_airport)
            for _ in range(num_hangars):
                height = random.randint(10, 30)
                width = random.randint(20, 60)
                hangar_length = random.randint(30, 100)
                lat, lon = self.random_coord()
                self.cursor.execute(
                    "INSERT INTO Hangar (airport_id, height, width, hangar_length, coordinates) "
                    "VALUES (%s, %s, %s, %s, ROW(%s,%s)::coord)",
                    (airport_id, height, width, hangar_length, lat, lon)
                )
        self.conn.commit()
        logging.info(f"Hangars inserted ({self.num_hangars_per_airport * len(self.airport_ids)} rows)")

    def fill_plane_position(self):
        for plane_id in self.plane_ids:
            num_positions = random.randint(2, self.num_positions_per_plane)
            base_time = self.fake.date_time_between(start_date='-30d', end_date='now')
            for i in range(num_positions):
                ttime = base_time + timedelta(minutes=random.randint(5, 60) * i)
                lat, lon = self.random_coord()
                direction = random.randint(0, 359)
                pitch = random.randint(-10, 30)
                speed = random.randint(0, 900)
                self.cursor.execute(
                    "INSERT INTO Plane_position (ttime, coordinates, plane_id, direction, pitch, speed) "
                    "VALUES (%s, ROW(%s,%s)::coord, %s, %s, %s, %s)",
                    (ttime, lat, lon, plane_id, direction, pitch, speed)
                )
        self.conn.commit()
        logging.info(f"Plane positions inserted ({self.num_planes * self.num_positions_per_plane} rows)")

    def fill_flight(self):
        for _ in range(self.num_flights):
            code_flight = self.fake.unique.random_number(digits=6)
            plane_id = random.choice(self.plane_ids) if self.plane_ids else None
            employee_id = random.choice(self.employee_ids) if self.employee_ids else None
            strip_take_off_id = random.choice(self.strip_ids) if self.strip_ids else None
            strip_landing_id = random.choice(self.strip_ids) if self.strip_ids else None
            take_off_airport_id = random.choice(self.airport_ids) if self.airport_ids else None
            landing_airport_id = random.choice(self.airport_ids) if self.airport_ids else None

            planed_take_off = self.fake.date_time_this_year()
            planed_landing = planed_take_off + timedelta(hours=random.randint(1, 12))
            take_off_time = planed_take_off + timedelta(minutes=random.randint(-30, 30))
            landing_time = planed_landing + timedelta(minutes=random.randint(-30, 30))
            actual_take_off = planed_take_off if random.random() > 0.3 else None
            actual_landing = planed_landing if random.random() > 0.3 else None

            self.cursor.execute(
                """INSERT INTO Flight (code_flight, plane_id, employee_id, strip_take_off_id, strip_landing_id,
                    take_off_airport_id, landing_airport_id, take_off_time, landing_time,
                    planed_take_off_time, planed_landing_time, actual_take_off_time, actual_landing_time)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING code_flight""",
                (code_flight, plane_id, employee_id, strip_take_off_id, strip_landing_id,
                 take_off_airport_id, landing_airport_id, take_off_time, landing_time,
                 planed_take_off, planed_landing, actual_take_off, actual_landing)
            )
            flight_id = self.cursor.fetchone()[0]
            self.flight_ids.append(flight_id)
        self.conn.commit()
        logging.info(f"{len(self.flight_ids)} flights added")

    def fill_mechanical_check(self):
        if not self.note_ids:
            logging.warning("No status logs for mechanical checks")
            return
        num_checks = min(self.num_mechanical_checks, len(self.note_ids))
        for _ in range(num_checks):
            note_id = random.choice(self.note_ids)
            plane_id = random.choice(self.plane_ids)
            self.cursor.execute("SELECT change_time FROM Status_log WHERE note_id = %s", (note_id,))
            base_time = self.cursor.fetchone()[0]
            check_start = base_time - timedelta(hours=random.randint(1, 12))
            check_end = base_time + timedelta(hours=random.randint(1, 12))
            self.cursor.execute(
                "INSERT INTO Mechanical_check (plane_id, note_id, checking_start, checking_end) "
                "VALUES (%s, %s, %s, %s)",
                (plane_id, note_id, check_start, check_end)
            )
        self.conn.commit()
        logging.info(f"{num_checks} mechanical checks inserted")

    def fill_flight_ticket(self):
        for flight_id in self.flight_ids:
            num_tickets = random.randint(5, self.num_tickets_per_flight)
            for _ in range(num_tickets):
                ticket_code = self.fake.unique.random_number(digits=10)
                self.cursor.execute(
                    "INSERT INTO Flight_ticket (ticket_code, code_flight) "
                    "VALUES (%s, %s) RETURNING ticket_code",
                    (ticket_code, flight_id)
                )
                ticket_code = self.cursor.fetchone()[0]
                self.ticket_codes.append(ticket_code)
        self.conn.commit()
        logging.info(f"{len(self.ticket_codes)} tickets added")

    def fill_passenger(self):
        if not self.ticket_codes:
            logging.warning("No tickets for passengers")
            return
        tickets_to_use = random.choices(self.ticket_codes, k=min(self.num_passengers, len(self.ticket_codes)))
        for ticket_code in tickets_to_use:
            name = self.fake.name()
            age = random.randint(1, 90)
            passport = self.fake.unique.random_number(digits=10)
            citizenship = "Russia"
            time_issuance = self.fake.date_between(start_date='-10y', end_date='today')
            department_code = self.fake.bothify(text='??######').upper()
            issued_by = self.fake.word().capitalize() + " Department"
            self.cursor.execute(
                """INSERT INTO Passenger (ticket_code, passenger_name, age, passport, citizenship_country,
                    time_issuance, department_code, issued_by) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                (ticket_code, name, age, passport, citizenship, time_issuance, department_code, issued_by)
            )
        self.conn.commit()
        logging.info(f"{len(tickets_to_use)} passengers added")

    def fill_strip_log(self):
        for _ in range(self.num_strip_logs):
            plane_id = random.choice(self.plane_ids) if self.plane_ids else None
            strip_id = random.choice(self.strip_ids) if self.strip_ids else None
            airport_id = random.choice(self.airport_ids) if self.airport_ids else None
            planes_number = random.randint(0, 10)
            dest_time = self.fake.date_time_between(start_date='-5d', end_date='+5d')
            let_go_time = dest_time + timedelta(minutes=random.randint(10, 120))
            self.cursor.execute(
                """INSERT INTO Strip_log (plane_id, strip_id, airport_id, planes_number, destination_time, let_go_time)
                   VALUES (%s, %s, %s, %s, %s, %s)""",
                (plane_id, strip_id, airport_id, planes_number, dest_time, let_go_time)
            )
        self.conn.commit()
        logging.info(f"{self.num_strip_logs} strip logs inserted")

    def generate_all(self):
        self.connect()
        try:
            self.fill_employee_position_duty()
            self.fill_airport()
            self.fill_plane()
            self.fill_strip()
            self.fill_employee()
            self.fill_status_log()
            self.fill_plane_position()
            self.fill_hangar()
            self.fill_flight()
            self.fill_mechanical_check()
            self.fill_flight_ticket()
            self.fill_passenger()
            self.fill_strip_log()
            logging.info("All data generated successfully")
        except Exception as e:
            self.conn.rollback()
            logging.error(f"Error during generation: {e}")
            raise
        finally:
            self.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    db_config = {
        'dbname': 'lab4',
        'user': 'sofia',
        'host': None,
        'port': 5432
    }
    filler = DataBaseFiller(db_config, num_airports=3, num_planes=10)
    filler.generate_all()