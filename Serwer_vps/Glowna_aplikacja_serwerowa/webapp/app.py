import os
import json
from datetime import datetime, timedelta, timezone
from functools import wraps

from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, g
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
from jwt import ExpiredSignatureError, InvalidTokenError
import mysql.connector
from mysql.connector import Error
import traceback

# ------------------------------------------------------------------------------
# KONFIGURACJA APLIKACJI
# ------------------------------------------------------------------------------

# Inicjalizacja głównego obiektu aplikacji Flask
# template_folder='templates': wskazuje katalog z plikami HTML (Jinja2)
# static_folder='static': wskazuje katalog z plikami statycznymi (CSS, JS, obrazy)
app = Flask(__name__, template_folder='templates', static_folder='static')

# Klucz sekretny używany do podpisywania sesji (cookies) oraz innych operacji kryptograficznych.
# W środowisku produkcyjnym powinien być pobierany ze zmiennych środowiskowych dla bezpieczeństwa.
app.secret_key = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')

# ------------------------------------------------------------------------------
# KONFIGURACJA FLASK-LOGIN
# ------------------------------------------------------------------------------

# Inicjalizacja menedżera logowania, który obsługuje sesje użytkowników
login_manager = LoginManager()
login_manager.init_app(app)

# Określenie widoku (endpointu), do którego użytkownik zostanie przekierowany,
# jeśli spróbuje wejść na stronę wymagającą logowania bez aktywnej sesji.
login_manager.login_view = 'login'
login_manager.login_message = 'Zaloguj się, aby uzyskać dostęp.'

# ------------------------------------------------------------------------------
# KONFIGURACJA BAZY DANYCH (MySQL)
# ------------------------------------------------------------------------------

# Pobieranie danych dostępowych do bazy danych ze zmiennych środowiskowych.
# Wartości domyślne są ustawione pod typową konfigurację deweloperską (np. Docker).
DB_HOST = os.getenv('DB_HOST', 'mysql')          # Adres hosta bazy danych
DB_USER = os.getenv('DB_USER', 'iot_user')       # Nazwa użytkownika bazy
DB_PASSWORD = os.getenv('DB_PASSWORD', 'mocne_haslo') # Hasło użytkownika
DB_NAME = os.getenv('DB_NAME', 'iot_db')         # Nazwa bazy danych

# ------------------------------------------------------------------------------
# KONFIGURACJA JWT (JSON Web Token)
# ------------------------------------------------------------------------------

# Klucz sekretny do podpisywania tokenów JWT (używanych w API).
# Jeśli nie podano JWT_SECRET, używany jest app.secret_key.
JWT_SECRET = os.getenv('JWT_SECRET', os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production'))

# Czas ważności tokena JWT w godzinach (domyślnie 12h).
JWT_EXP_HOURS = int(os.getenv('JWT_EXP_HOURS', '12'))


# ------------------------------------------------------------------------------
# FUNKCJE POMOCNICZE BAZY DANYCH
# ------------------------------------------------------------------------------

def get_db():
    """
    Tworzy i zwraca nowe połączenie do bazy danych MySQL.
    Wykorzystuje bibliotekę mysql.connector.
    
    Zwraca:
        mysql.connector.connection.MySQLConnection: Obiekt połączenia.
    """
    return mysql.connector.connect(
        host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_NAME
    )


def init_db():
    """
    Inicjalizuje strukturę bazy danych.
    Tworzy niezbędne tabele, jeśli jeszcze nie istnieją.
    Tworzy również domyślnego użytkownika administratora.
    Funkcja ta jest wywoływana przy starcie aplikacji.
    """
    cnx = get_db()
    cursor = cnx.cursor()

    # Tabela 'users': Przechowuje dane użytkowników systemu.
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(80) UNIQUE NOT NULL,
            email VARCHAR(120) UNIQUE NOT NULL,
            password_hash VARCHAR(256) NOT NULL,
            is_admin BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Tabela 'kurniki': Przechowuje informacje o monitorowanych obiektach (kurnikach).
    # owner_id: Klucz obcy do tabeli users (właściciel kurnika).
    # topic_id: Unikalny identyfikator używany w tematach MQTT (np. kurnik/topic_id).
    # Limity: min/max dla każdej metryki (NULL = brak limitu)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS kurniki (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            location VARCHAR(200),
            owner_id INT NOT NULL,
            topic_id VARCHAR(50) UNIQUE NOT NULL,
            temp_min FLOAT DEFAULT NULL,
            temp_max FLOAT DEFAULT NULL,
            hum_min FLOAT DEFAULT NULL,
            hum_max FLOAT DEFAULT NULL,
            co2_min INT DEFAULT NULL,
            co2_max INT DEFAULT NULL,
            nh3_min INT DEFAULT NULL,
            nh3_max INT DEFAULT NULL,
            sun_min INT DEFAULT NULL,
            sun_max INT DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
        )
    ''')
    
    # Dodanie kolumn do istniejącej tabeli (jeśli nie istnieją)
    for col in ['temp_min', 'temp_max', 'hum_min', 'hum_max']:
        try:
            cursor.execute(f"ALTER TABLE kurniki ADD COLUMN {col} FLOAT DEFAULT NULL")
        except:
            pass
    
    for col in ['co2_min', 'co2_max', 'nh3_min', 'nh3_max', 'sun_min', 'sun_max']:
        try:
            cursor.execute(f"ALTER TABLE kurniki ADD COLUMN {col} INT DEFAULT NULL")
        except:
            pass

    # Tabela 'kurniki_dane': Przechowuje historię pomiarów (telemetrię) z czujników.
    # Dane są zapisywane przez skrypt subskrybujący MQTT.
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS kurniki_dane (
            id INT AUTO_INCREMENT PRIMARY KEY,
            kurnik VARCHAR(20),      -- topic_id kurnika
            device_id INT,           -- ID urządzenia wewnątrz kurnika
            temp FLOAT,              -- Temperatura
            hum FLOAT,               -- Wilgotność
            co2 INT,                 -- Stężenie CO2
            nh3 INT,                 -- Stężenie NH3 (amoniak)
            sun INT,                 -- Poziom nasłonecznienia
            payload_raw TEXT,        -- Surowy payload (opcjonalnie)
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Tabela 'kury_meta': Przechowuje meta-dane kur (np. imiona) niezależnie od zdarzeń.
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS kury_meta (
            id INT AUTO_INCREMENT PRIMARY KEY,
            kurnik VARCHAR(50) NOT NULL,
            id_kury VARCHAR(50) NOT NULL,
            name VARCHAR(100) DEFAULT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uk_kurnik_idkury (kurnik, id_kury)
        )
    ''')
    
    # Migration: Change id_kury to VARCHAR in kury_meta if needed
    try:
        cursor.execute("ALTER TABLE kury_meta MODIFY COLUMN id_kury VARCHAR(50) NOT NULL")
    except:
        pass

    # Tabela 'devices': Przechowuje informacje o fizycznych urządzeniach przypisanych do kurników.
    # Przechowuje logiczne ID urządzenia i opcjonalną nazwę; nie przechowujemy już MAC.
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS devices (
            id INT AUTO_INCREMENT PRIMARY KEY,
            kurnik_id INT,
            device_id INT,           -- Logiczne ID urządzenia w kurniku (np. 1, 2, 3)
            name VARCHAR(100) DEFAULT NULL,  -- Opcjonalna nazwa urządzenia
            deleted TINYINT DEFAULT 0,
            paired_at DATETIME DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (kurnik_id) REFERENCES kurniki(id) ON DELETE CASCADE
        )
    ''')
    
    # Dodanie kolumn name/deleted do istniejącej tabeli (jeśli nie istnieją)
    try:
        cursor.execute("ALTER TABLE devices ADD COLUMN name VARCHAR(100) DEFAULT NULL")
    except:
        pass
    try:
        cursor.execute("ALTER TABLE devices ADD COLUMN deleted TINYINT DEFAULT 0")
    except:
        pass
    # Dodanie kolumny paired_at do istniejącej tabeli (jeśli nie istnieje)
    try:
        cursor.execute("ALTER TABLE devices ADD COLUMN paired_at DATETIME DEFAULT NULL")
    except:
        pass

    # (No hidden_devices table — devices removed by user are deleted from `devices` and can be recreated by telemetry.)

    # Tworzenie domyślnego konta administratora, jeśli nie istnieje.
    cursor.execute("SELECT id FROM users WHERE username = 'admin'")
    if not cursor.fetchone():
        admin_hash = generate_password_hash('admin123')
        cursor.execute(
            "INSERT INTO users (username, email, password_hash, is_admin) VALUES (%s, %s, %s, %s)",
            ('admin', 'admin@localhost', admin_hash, True)
        )
        print("Utworzono domyślnego administratora (admin/admin123)")

    cnx.commit()
    cursor.close()
    cnx.close()


def get_user_by_id(user_id):
    """
    Pobiera dane użytkownika z bazy na podstawie jego ID.
    
    Argumenty:
        user_id (int): ID użytkownika.
        
    Zwraca:
        dict: Słownik z danymi użytkownika lub None, jeśli nie znaleziono.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT id, username, email, is_admin FROM users WHERE id = %s", (user_id,))
    row = cursor.fetchone()
    cursor.close()
    cnx.close()
    return row


def get_user_by_username_or_email(identifier):
    """
    Pobiera dane użytkownika na podstawie nazwy użytkownika LUB adresu email.
    Używane przy logowaniu.
    
    Argumenty:
        identifier (str): Nazwa użytkownika lub email.
        
    Zwraca:
        dict: Słownik z danymi użytkownika (w tym hash hasła) lub None.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM users WHERE username = %s OR email = %s", (identifier, identifier))
    row = cursor.fetchone()
    cursor.close()
    cnx.close()
    return row


def get_kurnik_by_id_for_owner(kurnik_id, owner_id):
    """
    Pobiera dane kurnika, weryfikując jednocześnie czy należy on do podanego właściciela.
    Zabezpiecza przed dostępem do cudzych kurników.
    
    Argumenty:
        kurnik_id (int): ID kurnika.
        owner_id (int): ID użytkownika (właściciela).
        
    Zwraca:
        dict: Dane kurnika lub None.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute(
        "SELECT id, name, location, topic_id, owner_id, created_at FROM kurniki WHERE id = %s AND owner_id = %s",
        (kurnik_id, owner_id),
    )
    row = cursor.fetchone()
    cursor.close()
    cnx.close()
    return row


def _parse_iso8601(s):
    """
    Pomocnicza funkcja do parsowania daty w formacie ISO 8601 (np. z parametrów URL).
    Obsługuje sufiks 'Z' oznaczający UTC.
    
    Argumenty:
        s (str): Data w formacie string.
        
    Zwraca:
        datetime: Obiekt datetime (UTC naive) lub None w przypadku błędu.
    """
    if not s:
        return None
    try:
        # Zamiana 'Z' na '+00:00' dla kompatybilności z fromisoformat w starszych wersjach Pythona
        s2 = s.replace('Z', '+00:00')
        dt = datetime.fromisoformat(s2)
        # Konwersja do UTC i usunięcie informacji o strefie (dla zgodności z biblioteką mysql)
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except Exception:
        return None


# ------------------------------------------------------------------------------
# MODEL UŻYTKOWNIKA (Flask-Login)
# ------------------------------------------------------------------------------

class User(UserMixin):
    """
    Klasa reprezentująca użytkownika w kontekście Flask-Login.
    Dziedziczy po UserMixin, co zapewnia domyślne implementacje metod wymaganych przez Flask-Login
    (is_authenticated, is_active, is_anonymous, get_id).
    """
    def __init__(self, id, username, email, is_admin):
        self.id = id
        self.username = username
        self.email = email
        self.is_admin = is_admin


@login_manager.user_loader
def load_user(user_id):
    """
    Callback wymagany przez Flask-Login.
    Ładuje obiekt użytkownika na podstawie ID zapisanego w sesji.
    Wywoływany przy każdym żądaniu, jeśli użytkownik jest zalogowany.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT id, username, email, is_admin FROM users WHERE id = %s", (user_id,))
    row = cursor.fetchone()
    cursor.close()
    cnx.close()
    if row:
        return User(row['id'], row['username'], row['email'], row['is_admin'])
    return None


# ------------------------------------------------------------------------------
# OBSŁUGA JWT (Autoryzacja API)
# ------------------------------------------------------------------------------

def generate_jwt(user_id):
    """
    Generuje token JWT dla danego użytkownika.
    Token zawiera ID użytkownika ('sub') oraz datę wygaśnięcia ('exp').
    
    Argumenty:
        user_id (int): ID użytkownika.
        
    Zwraca:
        str: Zakodowany token JWT.
    """
    payload = {
        'sub': user_id,
        'exp': datetime.utcnow() + timedelta(hours=JWT_EXP_HOURS)
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm='HS256')
    # W nowszych wersjach PyJWT encode zwraca str, w starszych bytes.
    if isinstance(token, bytes):
        token = token.decode('utf-8')
    return token


def decode_jwt(token):
    """
    Dekoduje i weryfikuje token JWT.
    
    Argumenty:
        token (str): Token JWT.
        
    Zwraca:
        dict: Payload tokena lub słownik z błędem {'error': ...}.
    """
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
        return payload
    except ExpiredSignatureError:
        return {'error': 'token_expired'}
    except InvalidTokenError:
        return {'error': 'invalid_token'}


def token_required(f):
    """
    Dekorator dla endpointów API.
    Sprawdza obecność i poprawność tokena JWT w nagłówku Authorization.
    Jeśli token jest poprawny, ustawia g.current_user i pozwala na wykonanie funkcji.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get('Authorization', '')
        # Oczekiwany format: "Bearer <token>"
        if not auth.startswith('Bearer '):
            return jsonify({'error': 'authorization_required'}), 401
        
        token = auth.split(' ', 1)[1].strip()
        data = decode_jwt(token)
        
        if 'error' in data:
            return jsonify({'error': data['error']}), 401
        
        # Pobranie użytkownika z bazy na podstawie ID z tokena
        user_row = get_user_by_id(data.get('sub'))
        if not user_row:
            return jsonify({'error': 'user_not_found'}), 401
        
        # Zapisanie użytkownika w kontekście globalnym żądania (g)
        g.current_user = user_row
        
        # Obsługa kompatybilności wstecznej:
        # Jeśli dekorowana funkcja oczekuje argumentu (np. 'current_user'), przekazujemy go.
        try:
            import inspect
            sig = inspect.signature(f)
            params = list(sig.parameters.values())
            if params:
                first = params[0]
                # Sprawdzenie czy pierwszy argument może przyjąć wartość pozycyjną
                if first.kind in (inspect.Parameter.POSITIONAL_ONLY, inspect.Parameter.POSITIONAL_OR_KEYWORD):
                    return f(user_row, *args, **kwargs)
        except Exception:
            pass
            
        return f(*args, **kwargs)
    return decorated


def admin_required(f):
    """
    Dekorator dla widoków webowych.
    Wymaga, aby zalogowany użytkownik miał uprawnienia administratora (is_admin=True).
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            flash('Brak uprawnień administratora.', 'danger')
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    return decorated_function


# ------------------------------------------------------------------------------
# WIDOKI WEBOWE - AUTH (Logowanie i Rejestracja)
# ------------------------------------------------------------------------------

@app.route('/')
def index():
    """
    Strona główna (root).
    Przekierowuje zalogowanych do dashboardu, a niezalogowanych do logowania.
    """
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    return redirect(url_for('login'))


@app.route('/login', methods=['GET', 'POST'])
def login():
    """
    Widok logowania.
    GET: Wyświetla formularz logowania.
    POST: Weryfikuje dane i loguje użytkownika.
    """
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')

        cnx = get_db()
        cursor = cnx.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
        user_row = cursor.fetchone()
        cursor.close()
        cnx.close()

        # Weryfikacja hasła za pomocą werkzeug.security.check_password_hash
        if user_row and check_password_hash(user_row['password_hash'], password):
            user = User(user_row['id'], user_row['username'], user_row['email'], user_row['is_admin'])
            login_user(user)
            flash('Zalogowano pomyślnie.', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Nieprawidłowa nazwa użytkownika lub hasło.', 'danger')

    return render_template('login.html')


@app.route('/register', methods=['GET', 'POST'])
def register():
    """
    Widok rejestracji.
    GET: Wyświetla formularz rejestracji.
    POST: Tworzy nowe konto użytkownika.
    """
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        email = request.form.get('email', '').strip()
        password = request.form.get('password', '')
        password2 = request.form.get('password2', '')

        # Walidacja danych wejściowych
        errors = []
        if len(username) < 3:
            errors.append('Nazwa użytkownika musi mieć min. 3 znaki.')
        if '@' not in email:
            errors.append('Podaj poprawny adres e-mail.')
        if len(password) < 6:
            errors.append('Hasło musi mieć min. 6 znaków.')
        if password != password2:
            errors.append('Hasła nie są identyczne.')

        if not errors:
            cnx = get_db()
            cursor = cnx.cursor()
            try:
                # Zapis nowego użytkownika z hashowanym hasłem
                cursor.execute(
                    "INSERT INTO users (username, email, password_hash) VALUES (%s, %s, %s)",
                    (username, email, generate_password_hash(password))
                )
                cnx.commit()
                flash('Konto utworzone. Możesz się zalogować.', 'success')
                return redirect(url_for('login'))
            except mysql.connector.IntegrityError:
                # Obsługa błędu duplikatu (username lub email)
                errors.append('Użytkownik lub e-mail już istnieje.')
            finally:
                cursor.close()
                cnx.close()

        for e in errors:
            flash(e, 'danger')

    return render_template('register.html')


@app.route('/logout')
@login_required
def logout():
    """
    Wylogowanie użytkownika.
    Usuwa sesję i przekierowuje do strony logowania.
    """
    logout_user()
    flash('Wylogowano.', 'info')
    return redirect(url_for('login'))


# ------------------------------------------------------------------------------
# ENDPOINTY API - AUTH & PAROWANIE
# ------------------------------------------------------------------------------

@app.route('/api/v1/auth/me', methods=['GET'])
@token_required
def api_me():
    """
    API: Zwraca dane aktualnie zalogowanego użytkownika (na podstawie tokena).
    """
    try:
        user_row = getattr(g, 'current_user', None)
        if not user_row:
            return jsonify({'error': 'user_not_found'}), 404
        user = {
            'id': user_row.get('id'),
            'email': user_row.get('email'),
            'username': user_row.get('username'),
        }
        return jsonify(user), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': 'internal_error', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>/pair', methods=['POST'])
@token_required
def api_pair_farm(kurnik_id):
    """
    API: Parowanie urządzenia z kurnikiem.
    Dodaje wpis do tabeli 'devices', wiążąc adres MAC z kurnikiem.
    Wymaga uprawnień właściciela kurnika lub administratora.
    """
    try:
        user_row = getattr(g, 'current_user', None)
        if not user_row:
            return jsonify({'error': 'user_not_found'}), 401

        cnx = get_db()
        cursor = cnx.cursor(dictionary=True)
        
        # Sprawdzenie czy kurnik istnieje
        cursor.execute("SELECT * FROM kurniki WHERE id = %s", (kurnik_id,))
        kurnik = cursor.fetchone()
        if not kurnik:
            cursor.close()
            cnx.close()
            return jsonify({'error': 'kurnik_not_found'}), 404

        # Weryfikacja uprawnień
        if kurnik['owner_id'] != user_row['id'] and not user_row.get('is_admin'):
            cursor.close()
            cnx.close()
            return jsonify({'error': 'forbidden'}), 403

        data = request.get_json() or {}
        # Opcjonalna nazwa urządzenia
        device_name = data.get('name') or data.get('device_name')

        # Automatyczne przydzielanie kolejnego ID urządzenia w ramach tego kurnika
        cursor.execute('SELECT COALESCE(MAX(device_id), 0) as maxd FROM devices WHERE kurnik_id = %s', (kurnik_id,))
        row = cursor.fetchone()
        next_device_id = (row['maxd'] or 0) + 1

        # Domyślna nazwa, jeśli nie podano
        if not device_name:
            device_name = f"Urządzenie {next_device_id}"

        # Zapis urządzenia (bez pola mac)
            cursor.execute('INSERT INTO devices (kurnik_id, device_id, name, paired_at) VALUES (%s, %s, %s, NOW())', 
                (kurnik_id, next_device_id, device_name))
        cnx.commit()
        # don't expose internal DB id, use logical device_id for identification
        cursor.close()
        cnx.close()

        return jsonify({'ok': True, 'device_id': next_device_id, 'name': device_name}), 201
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': 'internal_error', 'message': str(e)}), 500


# ------------------------------------------------------------------------------
# WIDOKI WEBOWE - DASHBOARD (Panel Użytkownika)
# ------------------------------------------------------------------------------

@app.route('/dashboard')
@login_required
def dashboard():
    """
    Główny panel użytkownika.
    Wyświetla listę kurników należących do zalogowanego użytkownika.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM kurniki WHERE owner_id = %s ORDER BY name", (current_user.id,))
    kurniki = cursor.fetchall()
    cursor.close()
    cnx.close()
    return render_template('dashboard.html', kurniki=kurniki)


@app.route('/kurnik/new', methods=['GET', 'POST'])
@login_required
def kurnik_new():
    """
    Widok dodawania nowego kurnika.
    """
    if request.method == 'POST':
        name = request.form.get('name', '').strip()
        location = request.form.get('location', '').strip()
        topic_id = request.form.get('topic_id', '').strip()

        if not name or not topic_id:
            flash('Nazwa i Topic ID są wymagane.', 'danger')
        else:
            cnx = get_db()
            cursor = cnx.cursor()
            try:
                cursor.execute(
                    "INSERT INTO kurniki (name, location, owner_id, topic_id) VALUES (%s, %s, %s, %s)",
                    (name, location, current_user.id, topic_id)
                )
                cnx.commit()
                flash('Kurnik dodany.', 'success')
                return redirect(url_for('dashboard'))
            except mysql.connector.IntegrityError:
                flash('Topic ID już istnieje.', 'danger')
            finally:
                cursor.close()
                cnx.close()

    return render_template('kurnik_form.html', kurnik=None)


@app.route('/kurnik/<int:kurnik_id>')
@login_required
def kurnik_detail(kurnik_id):
    """
    Szczegółowy widok kurnika.
    Wyświetla:
    - Informacje o kurniku
    - Listę urządzeń z ich ostatnimi odczytami
    - Średnie statystyki z ostatnich 24h
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)

    # Pobranie danych kurnika
    cursor.execute("SELECT * FROM kurniki WHERE id = %s AND owner_id = %s", (kurnik_id, current_user.id))
    kurnik = cursor.fetchone()
    if not kurnik:
        cursor.close()
        cnx.close()
        flash('Kurnik nie znaleziony.', 'danger')
        return redirect(url_for('dashboard'))

    topic_id = kurnik['topic_id']

    # Pobranie listy ID urządzeń, które kiedykolwiek wysłały dane dla tego kurnika
    cursor.execute(
        '''
        SELECT DISTINCT device_id FROM kurniki_dane WHERE kurnik = %s ORDER BY device_id
        ''',
        (topic_id,)
    )
    devices = [r['device_id'] for r in cursor.fetchall()]

    # Pobranie ostatniego odczytu dla każdego z urządzeń
    device_stats = []
    for dev_id in devices:
        cursor.execute('''
            SELECT * FROM kurniki_dane
            WHERE kurnik = %s AND device_id = %s
            ORDER BY id DESC LIMIT 1
        ''', (topic_id, dev_id))
        row = cursor.fetchone()
        if row:
            device_stats.append(row)

    # Obliczenie średnich wartości z ostatnich 24 godzin dla całego kurnika
    cursor.execute('''
        SELECT
            AVG(temp) as avg_temp,
            AVG(hum) as avg_hum,
            AVG(co2) as avg_co2,
            AVG(nh3) as avg_nh3,
            AVG(sun) as avg_sun,
            COUNT(*) as readings_count
        FROM kurniki_dane
        WHERE kurnik = %s AND COALESCE(measurement_time, created_at) >= NOW() - INTERVAL 24 HOUR
    ''', (topic_id,))
    avg_stats = cursor.fetchone()

    # Pobranie listy kury (ostatnie zdarzenie dla każdej id_kury) powiązanych z tym kurnikiem
    chickens = []
    try:
        cursor.execute('SELECT DISTINCT id_kury FROM kury WHERE kurnik = %s ORDER BY id_kury', (topic_id,))
        ids = [r['id_kury'] for r in cursor.fetchall()]
        for kid in ids:
            cursor.execute('''
                SELECT id_kury, tryb_kury, waga, event_time, created_at
                FROM kury
                WHERE kurnik = %s AND id_kury = %s
                ORDER BY id DESC LIMIT 1
            ''', (topic_id, kid))
            crow = cursor.fetchone()
            if crow:
                # fetch persistent name from kury_meta if present
                try:
                    cursor.execute('SELECT name FROM kury_meta WHERE kurnik = %s AND id_kury = %s', (topic_id, kid))
                    nr = cursor.fetchone()
                    crow['name'] = nr.get('name') if nr else None
                except Exception:
                    crow['name'] = None
                chickens.append(crow)
    except Exception:
        # Jeśli tabela kury nie istnieje lub wystąpił błąd, zwracamy pustą listę
        chickens = []

    cursor.close()
    cnx.close()

    return render_template('kurnik_detail.html', kurnik=kurnik, devices=device_stats, avg_stats=avg_stats, chickens=chickens)


@app.route('/kurnik/<int:kurnik_id>/device/<int:device_id>')
@login_required
def device_detail(kurnik_id, device_id):
    """
    Szczegółowy widok konkretnego urządzenia w kurniku.
    Wyświetla statystyki specyficzne dla tego urządzenia.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM kurniki WHERE id=%s AND owner_id=%s", (kurnik_id, current_user.id))
    kurnik = cursor.fetchone()
    if not kurnik:
        cursor.close()
        cnx.close()
        flash('Kurnik nie znaleziony.', 'danger')
        return redirect(url_for('dashboard'))

    # Średnie wartości dla tego konkretnego urządzenia (ostatnie 24h)
    cursor.execute('''
        SELECT
            AVG(temp) as avg_temp,
            AVG(hum) as avg_hum,
            AVG(co2) as avg_co2,
            AVG(nh3) as avg_nh3,
            AVG(sun) as avg_sun
        FROM kurniki_dane
        WHERE kurnik = %s AND device_id = %s AND COALESCE(measurement_time, created_at) >= NOW() - INTERVAL 24 HOUR
    ''', (kurnik['topic_id'], device_id))
    avg = cursor.fetchone()

    cursor.close()
    cnx.close()

    return render_template('device_detail.html', kurnik=kurnik, device_id=device_id, avg=avg)


@app.route('/kurnik/<int:kurnik_id>/kura/<string:id_kury>')
@login_required
def kura_detail(kurnik_id, id_kury):
    """
    Szczegóły konkretnej kury (wszystkie zebrane zdarzenia dla tej kury).
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM kurniki WHERE id=%s AND owner_id=%s", (kurnik_id, current_user.id))
    kurnik = cursor.fetchone()
    if not kurnik:
        cursor.close(); cnx.close()
        flash('Kurnik nie znaleziony.', 'danger')
        return redirect(url_for('dashboard'))

    topic_id = kurnik['topic_id']
    try:
        cursor.execute('''
            SELECT id_kury, tryb_kury, waga, event_time, payload_raw, created_at
            FROM kury
            WHERE kurnik = %s AND id_kury = %s
            ORDER BY id DESC
        ''', (topic_id, id_kury))
        events = cursor.fetchall()
    except Exception:
        events = []

    # fetch persistent name if set
    try:
        cnx2 = get_db()
        cur2 = cnx2.cursor(dictionary=True)
        cur2.execute('SELECT name FROM kury_meta WHERE kurnik = %s AND id_kury = %s', (topic_id, id_kury))
        nr = cur2.fetchone()
        name = nr.get('name') if nr else None
        cur2.close(); cnx2.close()
    except Exception:
        name = None

    cursor.close(); cnx.close()
    return render_template('kura_detail.html', kurnik=kurnik, id_kury=id_kury, events=events, name=name)


@app.route('/kurnik/<int:kurnik_id>/kury/<string:id_kury>/name', methods=['POST'])
@login_required
def kura_set_name(kurnik_id, id_kury):
    """Web: Ustaw/aktualizuj imię kury (trwałe) z poziomu panelu webowego."""
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM kurniki WHERE id=%s AND owner_id=%s", (kurnik_id, current_user.id))
    kurnik = cursor.fetchone()
    if not kurnik:
        cursor.close(); cnx.close()
        flash('Kurnik nie znaleziony.', 'danger')
        return redirect(url_for('dashboard'))

    name = (request.form.get('name') or '').strip()[:100]
    topic_id = kurnik['topic_id']
    try:
        cursor.execute('INSERT INTO kury_meta (kurnik, id_kury, name) VALUES (%s, %s, %s) ON DUPLICATE KEY UPDATE name=VALUES(name), updated_at=CURRENT_TIMESTAMP', (topic_id, id_kury, name if name else None))
        cnx.commit()
        flash('Imię zapisane.', 'success')
    except Exception as e:
        cnx.rollback()
        traceback.print_exc()
        flash('Błąd zapisu imienia.', 'danger')
    finally:
        cursor.close(); cnx.close()
    return redirect(url_for('kurnik_detail', kurnik_id=kurnik_id))


@app.route('/kurnik/<int:kurnik_id>/kura/<string:id_kury>/delete', methods=['POST'])
@login_required
def kura_delete(kurnik_id, id_kury):
    """
    Usuwa wszystkie zdarzenia zapisane dla danej kury (id_kury) w danym kurniku.
    Wymaga bycia właścicielem kurnika.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM kurniki WHERE id=%s AND owner_id=%s", (kurnik_id, current_user.id))
    kurnik = cursor.fetchone()
    if not kurnik:
        cursor.close(); cnx.close()
        flash('Kurnik nie znaleziony.', 'danger')
        return redirect(url_for('dashboard'))

    topic_id = kurnik['topic_id']
    try:
        cursor2 = cnx.cursor()
        cursor2.execute("DELETE FROM kury WHERE kurnik = %s AND id_kury = %s", (topic_id, id_kury))
        cnx.commit()
        cursor2.close()
        flash('Usunięto zdarzenia kury.', 'success')
    except Exception as e:
        cnx.rollback()
        flash(f'Błąd podczas usuwania: {e}', 'danger')
    finally:
        cursor.close(); cnx.close()

    return redirect(url_for('kurnik_detail', kurnik_id=kurnik_id))


@app.route('/kurnik/<int:kurnik_id>/edit', methods=['GET', 'POST'])
@login_required
def kurnik_edit(kurnik_id):
    """
    Edycja danych kurnika (nazwa, lokalizacja, topic_id).
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT * FROM kurniki WHERE id = %s AND owner_id = %s", (kurnik_id, current_user.id))
    kurnik = cursor.fetchone()

    if not kurnik:
        cursor.close()
        cnx.close()
        flash('Kurnik nie znaleziony.', 'danger')
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        name = request.form.get('name', '').strip()
        location = request.form.get('location', '').strip()
        topic_id = request.form.get('topic_id', '').strip()

        if not name or not topic_id:
            flash('Nazwa i Topic ID są wymagane.', 'danger')
        else:
            try:
                cursor.execute(
                    "UPDATE kurniki SET name=%s, location=%s, topic_id=%s WHERE id=%s",
                    (name, location, topic_id, kurnik_id)
                )
                cnx.commit()
                flash('Kurnik zaktualizowany.', 'success')
                return redirect(url_for('kurnik_detail', kurnik_id=kurnik_id))
            except mysql.connector.IntegrityError:
                flash('Topic ID już istnieje.', 'danger')

    cursor.close()
    cnx.close()
    return render_template('kurnik_form.html', kurnik=kurnik)


@app.route('/kurnik/<int:kurnik_id>/delete', methods=['POST'])
@login_required
def kurnik_delete(kurnik_id):
    """
    Usuwanie kurnika.
    """
    cnx = get_db()
    cursor = cnx.cursor()
    cursor.execute("DELETE FROM kurniki WHERE id = %s AND owner_id = %s", (kurnik_id, current_user.id))
    cnx.commit()
    cursor.close()
    cnx.close()
    flash('Kurnik usunięty.', 'info')
    return redirect(url_for('dashboard'))


@app.route('/api/kurnik/<int:kurnik_id>/mesh_topology')
@login_required
def get_mesh_topology(kurnik_id):
    """
    Zwraca najnowszą topologię mesh dla danego kurnika.
    """
    try:
        cnx = get_db()
        cursor = cnx.cursor(dictionary=True)
        
        # Sprawdź czy użytkownik ma dostęp do tego kurnika
        cursor.execute("SELECT topic_id FROM kurniki WHERE id = %s AND owner_id = %s", (kurnik_id, current_user.id))
        kurnik = cursor.fetchone()
        
        if not kurnik:
            cursor.close()
            cnx.close()
            return jsonify({"error": "Kurnik not found or access denied"}), 404
        
        # Pobierz najnowszą topologię
        cursor.execute(
            """
            SELECT topology_json, created_at 
            FROM mesh_topology 
            WHERE kurnik = %s 
            ORDER BY created_at DESC 
            LIMIT 1
            """,
            (kurnik['topic_id'],)
        )
        topology = cursor.fetchone()
        cursor.close()
        cnx.close()
        
        if topology:
            return jsonify({
                "topology": json.loads(topology['topology_json']),
                "timestamp": topology['created_at'].isoformat() if topology['created_at'] else None
            })
        else:
            return jsonify({"topology": None, "timestamp": None})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ------------------------------------------------------------------------------
# WIDOKI WEBOWE - ADMIN PANEL
# ------------------------------------------------------------------------------

@app.route('/admin')
@login_required
@admin_required
def admin_panel():
    """
    Główny panel administratora.
    Wyświetla listę wszystkich użytkowników, kurników oraz statystyki bazy danych.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)

    # Lista wszystkich użytkowników
    cursor.execute("SELECT id, username, email, is_admin, created_at FROM users ORDER BY id")
    users = cursor.fetchall()

    # Lista wszystkich kurników z informacją o właścicielu
    cursor.execute("SELECT k.*, u.username as owner_name FROM kurniki k JOIN users u ON k.owner_id = u.id ORDER BY k.id")
    kurniki = cursor.fetchall()

    # Całkowita liczba pomiarów w bazie
    cursor.execute("SELECT COUNT(*) as cnt FROM kurniki_dane")
    readings_count = cursor.fetchone()['cnt']

    cursor.close()
    cnx.close()

    return render_template('admin.html', users=users, kurniki=kurniki, readings_count=readings_count)


@app.route('/admin/user/<int:user_id>/toggle_admin', methods=['POST'])
@login_required
@admin_required
def toggle_admin(user_id):
    """
    Akcja admina: Nadawanie/odbieranie uprawnień administratora.
    """
    if user_id == current_user.id:
        flash('Nie możesz zmienić własnych uprawnień.', 'danger')
        return redirect(url_for('admin_panel'))

    cnx = get_db()
    cursor = cnx.cursor()
    cursor.execute("UPDATE users SET is_admin = NOT is_admin WHERE id = %s", (user_id,))
    cnx.commit()
    cursor.close()
    cnx.close()
    flash('Uprawnienia zmienione.', 'success')
    return redirect(url_for('admin_panel'))


@app.route('/admin/user/<int:user_id>/delete', methods=['POST'])
@login_required
@admin_required
def delete_user(user_id):
    """
    Akcja admina: Usuwanie użytkownika z systemu.
    """
    if user_id == current_user.id:
        flash('Nie możesz usunąć siebie.', 'danger')
        return redirect(url_for('admin_panel'))

    cnx = get_db()
    cursor = cnx.cursor()
    cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))
    cnx.commit()
    cursor.close()
    cnx.close()
    flash('Użytkownik usunięty.', 'info')
    return redirect(url_for('admin_panel'))


@app.route('/admin/kurnik/<int:kurnik_id>/delete', methods=['POST'])
@login_required
@admin_required
def admin_delete_kurnik(kurnik_id):
    """
    Akcja admina: Usuwanie dowolnego kurnika.
    """
    cnx = get_db()
    cursor = cnx.cursor()
    cursor.execute("DELETE FROM kurniki WHERE id = %s", (kurnik_id,))
    cnx.commit()
    cursor.close()
    cnx.close()
    flash('Kurnik usunięty.', 'info')
    return redirect(url_for('admin_panel'))


@app.route('/admin/clear_db', methods=['POST'])
@login_required
@admin_required
def admin_clear_db():
    """
    Akcja admina: Czyszczenie całej tabeli z danymi pomiarowymi (kurniki_dane).
    Używane np. do resetu systemu.
    """
    cnx = get_db()
    cursor = cnx.cursor()
    try:
        cursor.execute('TRUNCATE TABLE kurniki_dane')
        cnx.commit()
        flash('Wyczyszczono wszystkie odczyty (kurniki_dane).', 'success')
    except Exception as e:
        cnx.rollback()
        flash(f'Błąd podczas czyszczenia bazy: {e}', 'danger')
    finally:
        cursor.close()
        cnx.close()
    return redirect(url_for('admin_panel'))


@app.route('/admin/devices')
@login_required
@admin_required
def admin_devices():
    """
    Widok admina: Lista wszystkich aktywnych urządzeń w systemie.
    Pokazuje statystyki: liczba odczytów, ostatnia aktywność.
    """
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    # Agregacja danych z tabeli pomiarowej
    cursor.execute('''
        SELECT kd.kurnik, kd.device_id, COUNT(*) as cnt, MAX(kd.created_at) as last_seen,
               k.id as kurnik_id, k.name as kurnik_name
        FROM kurniki_dane kd
        LEFT JOIN kurniki k ON k.topic_id = kd.kurnik
        LEFT JOIN devices d ON d.kurnik_id = k.id AND d.device_id = kd.device_id
        GROUP BY kd.kurnik, kd.device_id
        ORDER BY last_seen DESC
    ''')
    rows = cursor.fetchall()
    cursor.close()
    cnx.close()
    return render_template('admin_devices.html', rows=rows)


# ------------------------------------------------------------------------------
# KONFIGURACJA CORS
# ------------------------------------------------------------------------------

@app.after_request
def add_cors_headers(response):
    """
    Dodaje nagłówki CORS do każdej odpowiedzi.
    Umożliwia dostęp do API z innych domen (np. podczas developmentu frontendu).
    """
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,POST,PUT,DELETE,OPTIONS'
    return response


# ------------------------------------------------------------------------------
# REST API v1 (Dla aplikacji mobilnej i zewnętrznych klientów)
# ------------------------------------------------------------------------------

@app.route('/api/v1/auth/login', methods=['POST'])
def api_login():
    """
    API: Logowanie użytkownika.
    Przyjmuje JSON {username/email, password}.
    Zwraca token JWT.
    """
    data = request.get_json() or {}
    identifier = data.get('username') or data.get('email')
    password = data.get('password', '')
    if not identifier or not password:
        return jsonify({'error': 'missing_credentials'}), 400
    
    user_row = get_user_by_username_or_email(identifier)
    if not user_row or not check_password_hash(user_row['password_hash'], password):
        return jsonify({'error': 'invalid_credentials'}), 401
    
    token = generate_jwt(user_row['id'])
    return jsonify({
        'access_token': token,
        'user': {'id': user_row['id'], 'username': user_row['username'], 'email': user_row['email']}
    })


@app.route('/api/v1/auth/register', methods=['POST'])
def api_register():
    """
    API: Rejestracja użytkownika.
    Przyjmuje JSON {username, email, password}.
    Zwraca token JWT dla nowo utworzonego użytkownika.
    """
    data = request.get_json() or {}
    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip()
    password = data.get('password', '')
    
    if not username or not email or not password:
        return jsonify({'error': 'missing_fields'}), 400
    if len(password) < 6:
        return jsonify({'error': 'weak_password'}), 400
    
    cnx = get_db()
    cursor = cnx.cursor()
    try:
        cursor.execute(
            "INSERT INTO users (username, email, password_hash) VALUES (%s, %s, %s)",
            (username, email, generate_password_hash(password))
        )
        cnx.commit()
        user_id = cursor.lastrowid
        token = generate_jwt(user_id)
        return jsonify({
            'access_token': token,
            'user': {'id': user_id, 'username': username, 'email': email}
        }), 201
    except mysql.connector.IntegrityError:
        return jsonify({'error': 'user_exists'}), 409
    finally:
        cursor.close()
        cnx.close()


@app.route('/api/v1/coops', methods=['GET'])
@token_required
def api_coops():
    """
    API: Pobiera listę kurników zalogowanego użytkownika (z limitami).
    """
    user = g.current_user
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute('''
        SELECT id, name, location, topic_id, created_at,
               temp_min, temp_max, hum_min, hum_max,
               co2_min, co2_max, nh3_min, nh3_max,
               sun_min, sun_max
        FROM kurniki WHERE owner_id = %s ORDER BY name
    ''', (user['id'],))
    rows = cursor.fetchall()
    cursor.close()
    cnx.close()
    
    # Formatowanie limitów
    coops = []
    for row in rows:
        coop = {
            'id': row['id'],
            'name': row['name'],
            'location': row['location'],
            'topic_id': row['topic_id'],
            'created_at': row['created_at'],
            'limits': {
                'temperature': {'min': row.get('temp_min'), 'max': row.get('temp_max')},
                'humidity': {'min': row.get('hum_min'), 'max': row.get('hum_max')},
                'co2': {'min': row.get('co2_min'), 'max': row.get('co2_max')},
                'nh3': {'min': row.get('nh3_min'), 'max': row.get('nh3_max')},
                'sunlight': {'min': row.get('sun_min'), 'max': row.get('sun_max')}
            }
        }
        coops.append(coop)
    
    return jsonify({'coops': coops})


# Alias dla kompatybilności wstecznej
@app.route('/api/v1/farms', methods=['GET'])
@token_required
def api_farms():
    """API: Alias dla /api/v1/coops."""
    return api_coops()


@app.route('/api/v1/farms', methods=['POST'])
@token_required
def api_create_farm():
    """
    API: Tworzenie nowego kurnika.
    """
    user = g.current_user
    data = request.get_json() or {}
    topic = (data.get('topic') or data.get('topic_id') or data.get('mqtt_topic') or '').strip()
    name = (data.get('name') or '').strip()
    location = (data.get('location') or '').strip()

    if not topic or not name:
        return jsonify({'error': 'missing_fields', 'required': ['topic', 'name']}), 400

    cnx = get_db()
    cursor = cnx.cursor()
    try:
        cursor.execute(
            "INSERT INTO kurniki (name, location, owner_id, topic_id) VALUES (%s, %s, %s, %s)",
            (name, location, user['id'], topic),
        )
        cnx.commit()
        new_id = cursor.lastrowid
        cursor.close()
        cnx.close()

        # Pobranie utworzonego rekordu
        cnx2 = get_db()
        cur2 = cnx2.cursor(dictionary=True)
        cur2.execute("SELECT id, name, location, topic_id, created_at FROM kurniki WHERE id = %s", (new_id,))
        row = cur2.fetchone()
        cur2.close()
        cnx2.close()

        return jsonify(row), 201
    except mysql.connector.IntegrityError:
        try:
            cursor.close()
            cnx.close()
        except Exception:
            pass
        return jsonify({'error': 'topic_exists'}), 409
    except Exception as e:
        try:
            cursor.close()
            cnx.close()
        except Exception:
            pass
        traceback.print_exc()
        return jsonify({'error': 'internal_error', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>', methods=['PATCH'])
@token_required
def api_update_farm(kurnik_id):
    """
    API: Aktualizuje nazwę i/lub lokalizację (oraz opcjonalnie topic_id) kurnika.
    Body JSON: {"name": "...", "location": "...", "topic": "..."}
    Wymaga tokena. Tylko właściciel lub admin może aktualizować.
    """
    user = g.current_user
    data = request.get_json() or {}

    # Pobierz kurnik i sprawdź uprawnienia
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT id, owner_id FROM kurniki WHERE id = %s", (kurnik_id,))
    k = cursor.fetchone()
    if not k:
        cursor.close(); cnx.close()
        return jsonify({'error': 'not_found'}), 404

    if k['owner_id'] != user['id'] and not user.get('is_admin'):
        cursor.close(); cnx.close()
        return jsonify({'error': 'forbidden'}), 403

    updates = {}
    if 'name' in data:
        name = (data.get('name') or '').strip()
        if name:
            updates['name'] = name
    if 'location' in data:
        updates['location'] = (data.get('location') or '').strip()
    # dopuszczamy aktualizację topic_id (klucz mqtt) jeśli podano
    if 'topic' in data or 'topic_id' in data:
        topic = (data.get('topic') or data.get('topic_id') or '').strip()
        if topic:
            updates['topic_id'] = topic

    if not updates:
        cursor.close(); cnx.close()
        return jsonify({'error': 'no_updates'}), 400

    set_clause = ', '.join([f"{col} = %s" for col in updates.keys()])
    values = list(updates.values())
    values.append(kurnik_id)

    try:
        cursor2 = cnx.cursor()
        cursor2.execute(f"UPDATE kurniki SET {set_clause} WHERE id = %s", values)
        cnx.commit()
        cursor2.close()
    except mysql.connector.IntegrityError:
        cursor.close(); cnx.close()
        return jsonify({'error': 'topic_exists'}), 409
    except Exception as e:
        cursor.close(); cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'update_failed', 'message': str(e)}), 500

    # Zwróć zaktualizowany rekord
    try:
        cursor.execute("SELECT id, name, location, topic_id, created_at FROM kurniki WHERE id = %s", (kurnik_id,))
        row = cursor.fetchone()
    finally:
        cursor.close(); cnx.close()

    return jsonify(row), 200


@app.route('/api/v1/farms/<int:kurnik_id>', methods=['DELETE'])
@token_required
def api_delete_farm(kurnik_id):
    """
    API: Usuwa kurnik. Tylko właściciel lub admin.
    """
    user = g.current_user
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT id, owner_id FROM kurniki WHERE id = %s", (kurnik_id,))
    k = cursor.fetchone()
    if not k:
        cursor.close(); cnx.close()
        return jsonify({'error': 'not_found'}), 404

    if k['owner_id'] != user['id'] and not user.get('is_admin'):
        cursor.close(); cnx.close()
        return jsonify({'error': 'forbidden'}), 403

    try:
        cur2 = cnx.cursor()
        cur2.execute("DELETE FROM kurniki WHERE id = %s", (kurnik_id,))
        cnx.commit()
        cur2.close()
    except Exception as e:
        cursor.close(); cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'delete_failed', 'message': str(e)}), 500

    cursor.close(); cnx.close()
    return jsonify({'ok': True}), 200



@app.route('/api/v1/farms/<int:kurnik_id>/live', methods=['GET'])
@token_required
def api_farm_live(kurnik_id):
    """
    API: Pobiera najnowszy odczyt (live) dla danego kurnika.
    Zwraca dane z ostatniego wpisu w bazie dla tego topic_id.
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404

    topic_id = kurnik['topic_id']
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute(
        """
        SELECT COALESCE(measurement_time, created_at) as created_at, device_id, temp, hum, co2, nh3, sun
        FROM kurniki_dane
        WHERE kurnik = %s
        ORDER BY id DESC
        LIMIT 1
        """,
        (topic_id,),
    )
    row = cursor.fetchone()
    cursor.close()
    cnx.close()

    if not row:
        return jsonify({'data': {'ts': None}}), 200

    created_at = row.get('created_at')
    data = {
        'ts': created_at.isoformat() if created_at else None,
        'temperature': row.get('temp'),
        'humidity': row.get('hum'),
        'co2': row.get('co2'),
        'nh3': row.get('nh3'),
        'sunlight': row.get('sun'),
        'device_id': row.get('device_id'),
    }
    return jsonify({'data': data}), 200


@app.route('/api/v1/pair/status', methods=['GET'])
def api_pair_status():
    """
    API: Sprawdza, czy serwer odebrał jakiekolwiek dane z podanego tematu (topic).
    Używane przez aplikację mobilną podczas konfiguracji urządzenia, aby potwierdzić,
    że dane MQTT docierają do serwera.
    """
    topic = (request.args.get('topic') or '').strip()
    if not topic:
        return jsonify({'error': 'missing_topic'}), 400

    try:
        cnx = get_db()
        cursor = cnx.cursor(dictionary=True)
        # Sprawdzenie ostatniego wpisu dla danego tematu
        cursor.execute(
            "SELECT id, created_at FROM kurniki_dane WHERE LOWER(kurnik) = LOWER(%s) ORDER BY id DESC LIMIT 1",
            (topic,),
        )
        row = cursor.fetchone()
        cursor.close()
        cnx.close()

        if not row:
            return jsonify({'received': False, 'id': None, 'ts': None}), 200

        ts = row['created_at'].isoformat() if row.get('created_at') else None
        return jsonify({'received': True, 'id': row['id'], 'ts': ts}), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': 'internal_error', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>/history', methods=['GET'])
@token_required
def api_farm_history(kurnik_id):
    """
    API: Pobiera historię pomiarów dla wykresów.
    Parametry URL:
    - metric: nazwa metryki (temperature, humidity, co2, nh3, sunlight)
    - from: data początkowa (ISO 8601)
    - to: data końcowa (ISO 8601)
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404

    metric = (request.args.get('metric') or '').strip().lower()
    from_s = request.args.get('from')
    to_s = request.args.get('to')
    dt_from = _parse_iso8601(from_s)
    dt_to = _parse_iso8601(to_s)

    # Domyślny zakres: ostatnie 24h
    if not dt_to:
        dt_to = datetime.utcnow()
    if not dt_from:
        dt_from = dt_to - timedelta(hours=24)

    # Mapowanie nazw metryk na kolumny w bazie
    metric_to_col = {
        'temperature': 'temp',
        'humidity': 'hum',
        'co2': 'co2',
        'nh3': 'nh3',
        'sunlight': 'sun',
    }

    col = metric_to_col.get(metric)
    if not col:
        return jsonify([]), 200

    topic_id = kurnik['topic_id']
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)

    query = f"""
        SELECT COALESCE(measurement_time, created_at) as created_at, {col} as value
        FROM kurniki_dane
        WHERE kurnik = %s AND COALESCE(measurement_time, created_at) >= %s AND COALESCE(measurement_time, created_at) <= %s
        ORDER BY id ASC
        LIMIT 5000
    """
    cursor.execute(query, (topic_id, dt_from, dt_to))
    rows = cursor.fetchall()
    cursor.close()
    cnx.close()

    series = []
    for r in rows:
        ts = r.get('created_at')
        series.append({
            'ts': ts.isoformat() if ts else None,
            'value': r.get('value'),
        })

    return jsonify(series), 200


@app.route('/api/v1/series', methods=['GET'])
@token_required
def api_series_v1():
    """
    API: Pobiera surowe dane pomiarowe (wszystkie metryki).
    Używane do bardziej zaawansowanych wykresów.
    """
    topic = request.args.get('topic', '')
    device_id = request.args.get('device_id', None)
    hours = int(request.args.get('hours', 24))
    limit = int(request.args.get('limit', 1000))

    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)

    query = '''
        SELECT COALESCE(measurement_time, created_at) as ts, device_id, temp, hum, co2, nh3, sun
        FROM kurniki_dane
        WHERE kurnik = %s AND COALESCE(measurement_time, created_at) >= NOW() - INTERVAL %s HOUR
    '''
    params = [topic, hours]

    if device_id:
        query += ' AND device_id = %s'
        params.append(int(device_id))

    query += ' ORDER BY id DESC LIMIT %s'
    params.append(limit)

    cursor.execute(query, params)
    rows = cursor.fetchall()
    cursor.close()
    cnx.close()

    # Odwrócenie kolejności, aby najstarsze były pierwsze (dla wykresów)
    rows.reverse()
    data = []
    for r in rows:
        data.append({
            'ts': r['ts'].isoformat() if r['ts'] else None,
            'device_id': r['device_id'],
            'temp': r['temp'],
            'hum': r['hum'],
            'co2': r['co2'],
            'nh3': r['nh3'],
            'sun': r['sun'],
        })

    return jsonify({'topic': topic, 'data': data})


@app.route('/api/v1/farms/<int:kurnik_id>/alerts', methods=['GET'])
@token_required
def api_farm_alerts(kurnik_id):
    """
    API: Pobiera listę alertów dla kurnika.
    (Funkcjonalność w przygotowaniu - obecnie zwraca pustą listę lub dane z tabeli alerts jeśli istnieje).
    """
    user = g.current_user
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute("SELECT id, name, topic_id FROM kurniki WHERE id=%s AND owner_id=%s", (kurnik_id, user['id']))
    k = cursor.fetchone()
    if not k:
        cursor.close(); cnx.close()
        return jsonify({'error':'not_found'}), 404

    # Próba pobrania alertów (zakładając istnienie tabeli alerts)
    try:
        cursor.execute("SELECT id, message, level, created_at FROM alerts WHERE kurnik_id=%s ORDER BY created_at DESC LIMIT 100", (kurnik_id,))
        alerts = cursor.fetchall()
    except Exception:
        alerts = []
        
    cursor.close(); cnx.close()

    return jsonify({'alerts': alerts}), 200


# ------------------------------------------------------------------------------
# ENDPOINTY DLA WYKRESÓW WEBOWYCH (Sesja Cookie)
# ------------------------------------------------------------------------------

@app.route('/api/series')
@login_required
def api_series():
    """
    Wewnętrzne API dla frontendu webowego (wykresy w dashboardzie).
    Działa analogicznie do api_series_v1, ale uwierzytelnia się sesją (cookie), a nie tokenem.
    """
    topic = request.args.get('topic', '')
    device_id = request.args.get('device_id', None)
    hours = int(request.args.get('hours', 24))
    limit = int(request.args.get('limit', 1000))

    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)

    query = '''
        SELECT COALESCE(measurement_time, created_at) as ts, device_id, temp, hum, co2, nh3, sun
        FROM kurniki_dane
        WHERE kurnik = %s AND COALESCE(measurement_time, created_at) >= NOW() - INTERVAL %s HOUR
    '''
    params = [topic, hours]

    if device_id:
        query += ' AND device_id = %s'
        params.append(int(device_id))

    query += ' ORDER BY id DESC LIMIT %s'
    params.append(limit)

    cursor.execute(query, params)
    rows = cursor.fetchall()
    cursor.close()
    cnx.close()

    rows.reverse()
    data = []
    for r in rows:
        data.append({
            'ts': r['ts'].isoformat() if r['ts'] else None,
            'device_id': r['device_id'],
            'temp': r['temp'],
            'hum': r['hum'],
            'co2': r['co2'],
            'nh3': r['nh3'],
            'sun': r['sun'],
        })

    return jsonify({'topic': topic, 'data': data})


# ------------------------------------------------------------------------------
# API - LIMITY POMIARÓW
# ------------------------------------------------------------------------------

@app.route('/api/v1/farms/<int:kurnik_id>/limits', methods=['GET'])
@token_required
def api_get_farm_limits(kurnik_id):
    """
    API: Pobiera limity pomiarów dla kurnika.
    Zwraca min/max dla wszystkich metryk.
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    cursor.execute('''
        SELECT temp_min, temp_max, hum_min, hum_max, 
               co2_min, co2_max, nh3_min, nh3_max, 
               sun_min, sun_max
        FROM kurniki WHERE id = %s
    ''', (kurnik_id,))
    row = cursor.fetchone()
    cursor.close()
    cnx.close()
    
    if not row:
        return jsonify({'error': 'not_found'}), 404
    
    limits = {
        'temperature': {
            'min': row.get('temp_min'),
            'max': row.get('temp_max')
        },
        'humidity': {
            'min': row.get('hum_min'),
            'max': row.get('hum_max')
        },
        'co2': {
            'min': row.get('co2_min'),
            'max': row.get('co2_max')
        },
        'nh3': {
            'min': row.get('nh3_min'),
            'max': row.get('nh3_max')
        },
        'sunlight': {
            'min': row.get('sun_min'),
            'max': row.get('sun_max')
        }
    }
    
    return jsonify({'limits': limits}), 200


@app.route('/api/v1/farms/<int:kurnik_id>/limits', methods=['PUT', 'PATCH'])
@token_required
def api_update_farm_limits(kurnik_id):
    """
    API: Aktualizuje limity pomiarów dla kurnika.
    Przyjmuje JSON z limitami do zaktualizowania.
    Przykład:
    {
        "temperature": {"min": 15.0, "max": 25.0},
        "humidity": {"min": 40.0, "max": 70.0},
        "co2": {"max": 1000},
        "nh3": {"max": 50}
    }
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    
    data = request.get_json() or {}
    
    # Mapowanie nazw metryk na kolumny w bazie
    updates = {}
    
    if 'temperature' in data:
        if 'min' in data['temperature']:
            updates['temp_min'] = data['temperature']['min']
        if 'max' in data['temperature']:
            updates['temp_max'] = data['temperature']['max']
    
    if 'humidity' in data:
        if 'min' in data['humidity']:
            updates['hum_min'] = data['humidity']['min']
        if 'max' in data['humidity']:
            updates['hum_max'] = data['humidity']['max']
    
    if 'co2' in data:
        if 'min' in data['co2']:
            updates['co2_min'] = data['co2']['min']
        if 'max' in data['co2']:
            updates['co2_max'] = data['co2']['max']
    
    if 'nh3' in data:
        if 'min' in data['nh3']:
            updates['nh3_min'] = data['nh3']['min']
        if 'max' in data['nh3']:
            updates['nh3_max'] = data['nh3']['max']
    
    if 'sunlight' in data:
        if 'min' in data['sunlight']:
            updates['sun_min'] = data['sunlight']['min']
        if 'max' in data['sunlight']:
            updates['sun_max'] = data['sunlight']['max']
    
    if not updates:
        return jsonify({'error': 'no_updates'}), 400
    
    # Tworzenie zapytania UPDATE
    set_clause = ', '.join([f"{col} = %s" for col in updates.keys()])
    values = list(updates.values())
    values.append(kurnik_id)
    
    cnx = get_db()
    cursor = cnx.cursor()
    try:
        cursor.execute(f"UPDATE kurniki SET {set_clause} WHERE id = %s", values)
        cnx.commit()
        cursor.close()
        cnx.close()
        
        # Zwrócenie zaktualizowanych limitów
        return api_get_farm_limits(kurnik_id)
    except Exception as e:
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'update_failed', 'message': str(e)}), 500


@app.route('/api/v1/coops/<int:kurnik_id>/limits', methods=['GET'])
@token_required
def api_get_coop_limits(kurnik_id):
    """API: Alias dla /api/v1/farms/<id>/limits (GET)."""
    return api_get_farm_limits(kurnik_id)


@app.route('/api/v1/coops/<int:kurnik_id>/limits', methods=['PUT', 'PATCH'])
@token_required
def api_update_coop_limits(kurnik_id):
    """API: Alias dla /api/v1/farms/<id>/limits (PUT/PATCH)."""
    return api_update_farm_limits(kurnik_id)


# ------------------------------------------------------------------------------
# API - ZARZĄDZANIE URZĄDZENIAMI
# ------------------------------------------------------------------------------

@app.route('/api/v1/farms/<int:kurnik_id>/devices', methods=['GET'])
@token_required
def api_list_farm_devices(kurnik_id):
    """
    API: Pobiera listę wszystkich urządzeń wykrytych w kurniku.
    Zwraca urządzenia z pomiarów (`kurniki_dane`) oraz metadane z tabeli `devices` (np. `name`, `paired_at`).
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    
    topic_id = kurnik['topic_id']
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    
    # Pobierz unikalne device_id z pomiarów + info z tabeli devices (jeśli istnieje)
    cursor.execute('''
        SELECT DISTINCT 
            kd.device_id,
            d.name,
            d.paired_at as paired_at,
            MAX(kd.created_at) as last_seen
        FROM kurniki_dane kd
        LEFT JOIN devices d ON d.kurnik_id = %s AND d.device_id = kd.device_id
        WHERE kd.kurnik = %s AND (d.deleted IS NULL OR d.deleted = 0)
        GROUP BY kd.device_id, d.name, d.paired_at
        ORDER BY kd.device_id
    ''', (kurnik_id, topic_id))
    devices = cursor.fetchall()
    cursor.close()
    cnx.close()
    
    return jsonify({'devices': devices}), 200


@app.route('/api/v1/farms/<int:kurnik_id>/devices/<int:device_id>', methods=['PATCH'])
@token_required
def api_update_device(kurnik_id, device_id):
    """
    API: Aktualizuje nazwę urządzenia.
    Przyjmuje JSON: {"name": "Nowa nazwa"}
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    
    data = request.get_json() or {}
    device_name = data.get('name')
    
    if device_name is None:
        return jsonify({'error': 'missing_name'}), 400
    
    cnx = get_db()
    cursor = cnx.cursor()
    try:
        # Sprawdzenie czy urządzenie (logical device_id) należy do tego kurnika
        cursor.execute('SELECT id FROM devices WHERE device_id = %s AND kurnik_id = %s', (device_id, kurnik_id))
        row = cursor.fetchone()
        if not row:
            # Jeśli urządzenie nie jest sparsowane, utwórz wpis z podaną nazwą (upsert)
            try:
                cursor.execute('INSERT INTO devices (kurnik_id, device_id, name, paired_at, deleted) VALUES (%s, %s, %s, NOW(), %s)',
                               (kurnik_id, device_id, device_name, 0))
                cnx.commit()
            except Exception:
                cnx.rollback()
                cursor.close()
                cnx.close()
                traceback.print_exc()
                return jsonify({'error': 'create_failed'}), 500
            cursor.close()
            cnx.close()
            return jsonify({'ok': True, 'name': device_name, 'created': True}), 201
        
        # Aktualizacja nazwy istniejącego wpisu
        cursor.execute('UPDATE devices SET name = %s WHERE device_id = %s AND kurnik_id = %s', (device_name, device_id, kurnik_id))
        cnx.commit()
        cursor.close()
        cnx.close()
        
        return jsonify({'ok': True, 'name': device_name}), 200
    except Exception as e:
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'update_failed', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>/devices/<int:device_id>', methods=['DELETE'])
@token_required
def api_delete_device(kurnik_id, device_id):
    """
    API: Usuwa urządzenie z kurnika.
    Usuwa wpis z tabeli devices.
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    
    cnx = get_db()
    cursor = cnx.cursor()
    try:
        # Usuń rekord z tabeli devices. Telemetria pozostaje w kurniki_dane.
        try:
            cursor.execute('DELETE FROM devices WHERE device_id = %s AND kurnik_id = %s', (device_id, kurnik_id))
            cnx.commit()
        except Exception:
            cnx.rollback()
            cursor.close()
            cnx.close()
            traceback.print_exc()
            return jsonify({'error': 'delete_failed'}), 500

        cursor.close()
        cnx.close()
        return jsonify({'ok': True, 'deleted': True}), 200
    except Exception as e:
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'delete_failed', 'message': str(e)}), 500


@app.route('/api/v1/coops/<int:kurnik_id>/devices', methods=['GET'])
@token_required
def api_list_coop_devices(kurnik_id):
    """API: Alias dla /api/v1/farms/<id>/devices (GET)."""
    return api_list_farm_devices(kurnik_id)


@app.route('/api/v1/coops/<int:kurnik_id>/devices/<int:device_id>', methods=['PATCH'])
@token_required
def api_update_coop_device(kurnik_id, device_id):
    """API: Alias dla /api/v1/farms/<id>/devices/<id> (PATCH)."""
    return api_update_device(kurnik_id, device_id)


@app.route('/api/v1/coops/<int:kurnik_id>/devices/<int:device_id>', methods=['DELETE'])
@token_required
def api_delete_coop_device(kurnik_id, device_id):
    """API: Alias dla /api/v1/farms/<id>/devices/<id> (DELETE)."""
    return api_delete_device(kurnik_id, device_id)


# ------------------------------------------------------------------------------
# API - ZARZĄDZANIE KURAMI
# ------------------------------------------------------------------------------

@app.route('/api/v1/farms/<int:kurnik_id>/kury', methods=['GET'])
@token_required
def api_list_farm_chickens(kurnik_id):
    """
    Zwraca listę unikalnych kur (id_kury) wraz z ostatnim zdarzeniem dla każdej.
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404

    topic_id = kurnik['topic_id']
    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    try:
        cursor.execute('SELECT DISTINCT id_kury FROM kury WHERE kurnik = %s ORDER BY id_kury', (topic_id,))
        ids = [r['id_kury'] for r in cursor.fetchall()]
        chickens = []
        for kid in ids:
            cursor.execute('''
                SELECT id_kury, tryb_kury, waga, event_time, created_at
                FROM kury
                WHERE kurnik = %s AND id_kury = %s
                ORDER BY id DESC LIMIT 1
            ''', (topic_id, kid))
            row = cursor.fetchone()
            name = None
            # fetch persistent name from kury_meta if present
            try:
                cursor.execute('SELECT name FROM kury_meta WHERE kurnik = %s AND id_kury = %s', (topic_id, kid))
                nr = cursor.fetchone()
                if nr:
                    name = nr.get('name')
            except Exception:
                name = None
            if row:
                chickens.append({
                    'id_kury': row['id_kury'],
                    'tryb_kury': row['tryb_kury'],
                    'waga': row['waga'],
                    'name': name,
                    'event_time': row['event_time'].isoformat() if row.get('event_time') else None,
                    'last_seen': row['created_at'].isoformat() if row.get('created_at') else None
                })
        cursor.close()
        cnx.close()
        return jsonify({'chickens': chickens}), 200
    except Exception as e:
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'internal_error', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>/kury/<string:id_kury>', methods=['GET'])
@token_required
def api_get_chicken_events(kurnik_id, id_kury):
    """
    Pobiera zdarzenia dla konkretnej kury. Opcjonalne parametry: limit, since, until
    """
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404

    topic_id = kurnik['topic_id']
    limit = int(request.args.get('limit', 100))
    since_str = request.args.get('since')
    until_str = request.args.get('until')

    cnx = get_db()
    cursor = cnx.cursor(dictionary=True)
    try:
        query = 'SELECT id_kury, tryb_kury, waga, event_time, payload_raw, created_at FROM kury WHERE kurnik = %s AND id_kury = %s'
        params = [topic_id, id_kury]
        if since_str:
            dt_since = _parse_iso8601(since_str)
            if dt_since:
                query += ' AND COALESCE(event_time, created_at) >= %s'
                params.append(dt_since)
        if until_str:
            dt_until = _parse_iso8601(until_str)
            if dt_until:
                query += ' AND COALESCE(event_time, created_at) <= %s'
                params.append(dt_until)
        query += ' ORDER BY id DESC LIMIT %s'
        params.append(limit)
        cursor.execute(query, params)
        rows = cursor.fetchall()
        events = []
        for r in rows:
            events.append({
                'id_kury': r['id_kury'],
                'tryb_kury': r['tryb_kury'],
                'waga': r['waga'],
                'event_time': r['event_time'].isoformat() if r.get('event_time') else None,
                'payload_raw': r.get('payload_raw'),
                'created_at': r['created_at'].isoformat() if r.get('created_at') else None
            })
        # fetch persistent name if available
        try:
            cursor.execute('SELECT name FROM kury_meta WHERE kurnik = %s AND id_kury = %s', (topic_id, id_kury))
            nr = cursor.fetchone()
            name = nr.get('name') if nr else None
        except Exception:
            name = None
        cursor.close()
        cnx.close()
        return jsonify({'name': name, 'events': events}), 200
    except Exception as e:
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'internal_error', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>/kury/<string:id_kury>', methods=['DELETE'])
@token_required
def api_delete_chicken(kurnik_id, id_kury):
    """Usuwa wszystkie zdarzenia dla danej kury."""
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    topic_id = kurnik['topic_id']
    cnx = get_db()
    cursor = cnx.cursor()
    try:
        cursor.execute('DELETE FROM kury WHERE kurnik = %s AND id_kury = %s', (topic_id, id_kury))
        deleted_count = cursor.rowcount
        cnx.commit()
        cursor.close()
        cnx.close()
        return jsonify({'ok': True, 'deleted_count': deleted_count}), 200
    except Exception as e:
        cnx.rollback()
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'delete_failed', 'message': str(e)}), 500


@app.route('/api/v1/farms/<int:kurnik_id>/kury/<string:id_kury>/name', methods=['PUT', 'PATCH'])
@token_required
def api_set_chicken_name(kurnik_id, id_kury):
    """Ustawia lub aktualizuje imię kury (trwałe) dla danego kurnika i id_kury."""
    user = g.current_user
    kurnik = get_kurnik_by_id_for_owner(kurnik_id, user['id'])
    if not kurnik:
        return jsonify({'error': 'not_found'}), 404
    topic_id = kurnik['topic_id']
    data = request.get_json(silent=True) or {}
    name = data.get('name') if isinstance(data, dict) else None
    if name is None:
        return jsonify({'error': 'missing_name'}), 400
    name = str(name).strip()[:100]

    cnx = get_db()
    cursor = cnx.cursor()
    try:
        cursor.execute(
            'INSERT INTO kury_meta (kurnik, id_kury, name) VALUES (%s, %s, %s) ON DUPLICATE KEY UPDATE name = VALUES(name), updated_at = CURRENT_TIMESTAMP',
            (topic_id, id_kury, name)
        )
        cnx.commit()
        cursor.close()
        cnx.close()
        return jsonify({'ok': True, 'name': name}), 200
    except Exception as e:
        cnx.rollback()
        cursor.close()
        cnx.close()
        traceback.print_exc()
        return jsonify({'error': 'db_error', 'message': str(e)}), 500


# ------------------------------------------------------------------------------
# URUCHAMIANIE APLIKACJI
# ------------------------------------------------------------------------------

# Inicjalizacja bazy danych przy starcie aplikacji
with app.app_context():
    try:
        init_db()
    except Exception as e:
        print(f"DB init error (will retry on first request): {e}")


if __name__ == '__main__':
    # Uruchomienie serwera deweloperskiego
    PORT = int(os.getenv('PORT', '5000'))
    app.run(host='0.0.0.0', port=PORT, debug=True)


# ------------------------------------------------------------------------------
# FUNKCJE POMOCNICZE DLA DOCKERA
# ------------------------------------------------------------------------------

def ensure_tables_exist():
    """
    Sprawdza dostępność bazy danych i istnienie tabel.
    Używane w pętli retry przy starcie kontenera.
    """
    try:
        cnx = get_db()
        cursor = cnx.cursor()
        cursor.execute("SELECT 1 FROM users LIMIT 1")
        cursor.close()
        cnx.close()
    except Exception:
        try:
            init_db()
        except Exception as e:
            print('Failed to initialize DB schema:', e)


import time

# Pętla oczekująca na gotowość bazy danych (przydatne w Docker Compose)
for _ in range(10):
    try:
        ensure_tables_exist()
        break
    except Exception as e:
        print("DB init attempt failed:", e)
        time.sleep(2)

