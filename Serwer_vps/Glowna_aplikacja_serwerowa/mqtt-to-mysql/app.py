import os
import time
import json
from datetime import datetime
from typing import Optional, Tuple

import mysql.connector
import paho.mqtt.client as mqtt

MQTT_BROKER = os.getenv("MQTT_BROKER", "mosquitto")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER", "esp8266")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "esp8266")
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "kurnik/#")

DB_HOST = os.getenv("DB_HOST", "mysql")
DB_USER = os.getenv("DB_USER", "iot_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "iot_db")


def get_kurnik_from_topic(topic: str) -> str:
    parts = topic.split("/")
    return parts[1] if len(parts) > 1 else "unknown"


def parse_csv_payload(payload: str) -> Optional[Tuple[int, float, float, int, int, int, str]]:
    fields = [f.strip() for f in payload.split(";")]
    if len(fields) != 7:
        return None

    try:
        device_id = int(fields[0])
        temp = float(fields[1])
        hum = float(fields[2])
        co2 = int(fields[3])
        nh3 = int(fields[4])
        sun = int(fields[5])
        timestamp_str = fields[6]
    except (ValueError, IndexError):
        return None

    return device_id, temp, hum, co2, nh3, sun, timestamp_str


def parse_kury_payload(payload: str) -> Optional[Tuple[str, str, float, str]]:
    # Expected format: device_id;id_kury_hex;waga_gramy;DateTime
    # Example: 692641124;F7474A39;19100;00:08:35 Thu, Jan 29 2026
    # id_kury is hex string, waga is in grams (will be converted to kg)
    fields = [f.strip() for f in payload.split(";")]
    if len(fields) != 4:
        return None
    try:
        device_id = fields[0]     # Device/sensor ID (numeric string or hex)
        id_kury = fields[1]       # Chicken ID (hex string like F7474A39)
        waga_gramy = float(fields[2])  # Weight in grams
        waga = waga_gramy / 1000.0     # Convert grams to kg
        timestamp_str = fields[3] # Timestamp
    except (ValueError, IndexError):
        return None
    return id_kury, device_id, waga, timestamp_str


def connect_mysql_with_retry(max_seconds: int = 90):
    deadline = time.time() + max_seconds
    last_err: Optional[Exception] = None

    while time.time() < deadline:
        try:
            return mysql.connector.connect(
                host=DB_HOST,
                user=DB_USER,
                password=DB_PASSWORD,
                database=DB_NAME,
                autocommit=True,
            )
        except Exception as e:
            last_err = e
            print(f"MySQL not ready yet: {e}. Retrying...")
            time.sleep(2)

    raise RuntimeError(f"Failed to connect to MySQL within {max_seconds}s") from last_err


def ensure_schema(conn) -> None:
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS kurniki_dane (
          id INT AUTO_INCREMENT PRIMARY KEY,
          kurnik VARCHAR(50),
          device_id INT,
          temp FLOAT,
          hum  FLOAT,
          co2  INT,
          nh3  INT,
          sun  INT,
          payload_raw TEXT,
          measurement_time DATETIME,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """
    )

    # Migration: Add measurement_time column if it doesn't exist
    try:
        cursor.execute(
            """
            ALTER TABLE kurniki_dane 
            ADD COLUMN measurement_time DATETIME
            """
        )
        print("Added measurement_time column to existing table")
    except Exception as e:
        if "Duplicate column name" not in str(e):
            print(f"Migration note: {e}")

    # Create new table for chicken events
    try:
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS kury (
              id INT AUTO_INCREMENT PRIMARY KEY,
              kurnik VARCHAR(50),
              device_id VARCHAR(50),
              id_kury VARCHAR(50),
              tryb_kury TINYINT,
              waga FLOAT,
              event_time DATETIME,
              payload_raw TEXT,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
    except Exception as e:
        print(f"Failed to ensure kury table: {e}")
    
    # Migration: Change device_id and id_kury to VARCHAR if needed
    try:
        cursor.execute(
            """
            ALTER TABLE kury 
            MODIFY COLUMN device_id VARCHAR(50)
            """
        )
        print("Modified device_id column in kury table to VARCHAR(50)")
    except Exception as e:
        if "duplicate" not in str(e).lower() and "check" not in str(e).lower():
            print(f"Migration note for kury.device_id: {e}")
    
    try:
        cursor.execute(
            """
            ALTER TABLE kury 
            MODIFY COLUMN id_kury VARCHAR(50)
            """
        )
        print("Modified id_kury column in kury table to VARCHAR(50)")
    except Exception as e:
        if "duplicate" not in str(e).lower() and "check" not in str(e).lower():
            print(f"Migration note for kury.id_kury: {e}")

    # Create table for mesh topology
    try:
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS mesh_topology (
              id INT AUTO_INCREMENT PRIMARY KEY,
              kurnik VARCHAR(50),
              topology_json TEXT,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              INDEX idx_kurnik_created (kurnik, created_at DESC)
            )
            """
        )
    except Exception as e:
        print(f"Failed to ensure mesh_topology table: {e}")

    cursor.close()


def main() -> None:
    db = connect_mysql_with_retry()
    ensure_schema(db)

    def on_connect(client, userdata, flags, reason_code, properties=None):
        print("Connected to MQTT, reason_code=", reason_code)
        client.subscribe(MQTT_TOPIC)

    def on_message(client, userdata, msg):
        kurnik = get_kurnik_from_topic(msg.topic)
        payload_str = msg.payload.decode("utf-8", errors="replace").strip()

        # Handle mesh topology messages
        if msg.topic.rstrip("/").endswith("/mesh/topology") or msg.topic.split("/")[-1] == "topology":
            try:
                topology_data = json.loads(payload_str)
                # Validate basic structure
                if "nodeId" in topology_data:
                    c = db.cursor()
                    c.execute(
                        """
                        INSERT INTO mesh_topology (kurnik, topology_json)
                        VALUES (%s, %s)
                        """,
                        (kurnik, payload_str),
                    )
                    c.close()
                    print(f"Saved mesh topology for {kurnik}: {topology_data.get('nodeId')}")
                else:
                    print(f"Invalid topology JSON (missing nodeId): {payload_str}")
            except json.JSONDecodeError as e:
                print(f"Failed to parse mesh topology JSON: {e}, payload: {payload_str}")
            except Exception as e:
                print(f"Failed to save mesh topology: {e}")
            return

        # If topic ends with /kury -> parse chicken event
        if msg.topic.rstrip("/").endswith("/kury") or msg.topic.split("/")[-1] == "kury":
            parsed_kury = parse_kury_payload(payload_str)
            if parsed_kury is None:
                print("Bad kury payload (expected 4 semicolon-separated fields):", msg.topic, payload_str)
                return
            id_kury, device_id, waga, timestamp_str = parsed_kury  # id_kury is hex string, waga is in kg
            try:
                event_time = datetime.strptime(timestamp_str, "%H:%M:%S %a, %b %d %Y")
            except ValueError as e:
                print(f"Bad kury timestamp format: {timestamp_str}, error: {e}")
                event_time = None

            try:
                c = db.cursor()
                
                # Determine tryb_kury (mode): toggle between in/out of coop
                # First check if chicken exists and get its last mode
                c.execute(
                    """SELECT tryb_kury FROM kury 
                       WHERE kurnik = %s AND id_kury = %s 
                       ORDER BY id DESC LIMIT 1""",
                    (kurnik, id_kury)
                )
                last_entry = c.fetchone()
                
                if last_entry is None:
                    # New chicken - first entry means chicken is IN the coop
                    tryb_kury = 1
                    # Auto-create entry in kury_meta for new chicken
                    try:
                        c.execute(
                            """INSERT INTO kury_meta (kurnik, id_kury, name) 
                               VALUES (%s, %s, %s)
                               ON DUPLICATE KEY UPDATE kurnik=kurnik""",
                            (kurnik, id_kury, f"Kura {id_kury}")
                        )
                        print(f"Auto-created kury_meta entry for new chicken: {id_kury}")
                    except Exception as meta_err:
                        print(f"Failed to create kury_meta entry: {meta_err}")
                else:
                    # Toggle mode: 1 (in coop) <-> 0 (outside coop)
                    last_mode = last_entry[0]
                    tryb_kury = 0 if last_mode == 1 else 1
                
                # Save the event with determined mode
                c.execute(
                    """
                    INSERT INTO kury
                      (kurnik, device_id, id_kury, tryb_kury, waga, event_time, payload_raw)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (kurnik, device_id, id_kury, tryb_kury, waga, event_time, payload_str),
                )
                
                status_text = "w kurniku" if tryb_kury == 1 else "poza kurnikiem"
                print(f"Saved kury event: {kurnik}, kura {id_kury}, {status_text}, waga {waga}kg @ {event_time}")
                c.close()
            except Exception as e:
                print(f"Failed to save kury event: {e}")
            return

        # Otherwise handle sensor payloads
        parsed = parse_csv_payload(payload_str)
        if parsed is None:
            print("Bad payload (expected 7 semicolon-separated fields):", msg.topic, payload_str)
            return

        device_id, temp, hum, co2, nh3, sun, timestamp_str = parsed

        # Parse timestamp from format: "14:30:04 Tue, Jan 06 2026"
        try:
            measurement_time = datetime.strptime(timestamp_str, "%H:%M:%S %a, %b %d %Y")
        except ValueError as e:
            print(f"Bad timestamp format: {timestamp_str}, error: {e}")
            measurement_time = None

        # Ensure a devices row exists for this kurnik/device_id (auto-create if missing)
        try:
            c2 = db.cursor()
            c2.execute("SELECT id FROM kurniki WHERE topic_id = %s", (kurnik,))
            krow = c2.fetchone()
            if krow:
                kurnik_id = krow[0]
                c2.execute("SELECT id FROM devices WHERE kurnik_id = %s AND device_id = %s", (kurnik_id, device_id))
                row = c2.fetchone()
                default_name = f"Urządzenie {device_id}"
                if not row:
                    try:
                        if measurement_time:
                            c2.execute(
                                "INSERT INTO devices (kurnik_id, device_id, name, paired_at) VALUES (%s, %s, %s, %s)",
                                (kurnik_id, device_id, default_name, measurement_time),
                            )
                        else:
                            c2.execute(
                                "INSERT INTO devices (kurnik_id, device_id, name, paired_at) VALUES (%s, %s, %s, NOW())",
                                (kurnik_id, device_id, default_name),
                            )
                        print(f"Auto-created device entry for kurnik_id={kurnik_id} device_id={device_id}")
                    except Exception as e:
                        print(f"Failed to auto-create device entry: {e}")
                else:
                    try:
                        c2.execute("SELECT name, paired_at FROM devices WHERE kurnik_id = %s AND device_id = %s", (kurnik_id, device_id))
                        info = c2.fetchone()
                        name_val = info[0] if info else None
                        paired_val = info[1] if info and len(info) > 1 else None
                        if name_val is None or paired_val is None:
                            if measurement_time:
                                c2.execute(
                                    "UPDATE devices SET name = %s, paired_at = %s WHERE kurnik_id = %s AND device_id = %s",
                                    (default_name, measurement_time, kurnik_id, device_id),
                                )
                            else:
                                c2.execute(
                                    "UPDATE devices SET name = %s, paired_at = NOW() WHERE kurnik_id = %s AND device_id = %s",
                                    (default_name, kurnik_id, device_id),
                                )
                            print(f"Restored device metadata for kurnik_id={kurnik_id} device_id={device_id}")
                    except Exception as e:
                        print(f"Failed to restore device metadata: {e}")
            c2.close()
        except Exception as e:
            print(f"Device auto-create check failed: {e}")

        cursor = db.cursor()
        cursor.execute(
            """
            INSERT INTO kurniki_dane
              (kurnik, device_id, temp, hum, co2, nh3, sun, payload_raw, measurement_time)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (kurnik, device_id, temp, hum, co2, nh3, sun, payload_str, measurement_time),
        )
        cursor.close()

        print("Saved:", kurnik, device_id, temp, hum, co2, nh3, sun, "@", measurement_time)

    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
        client = mqtt.Client()

    client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.on_connect = on_connect
    client.on_message = on_message

    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_forever()


if __name__ == "__main__":
    main()
