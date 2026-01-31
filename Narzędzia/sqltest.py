import requests

def test_sql_injection_vulnerability(url, login_field, password_field):
    """
    Testuje odporność formularza na podstawowe błędy składni SQL.
    Nie przeprowadza ataku, jedynie sprawdza sanitację danych.
    """
    # Testowy payload - pojedynczy cudzysłów, który "łamie" zapytanie w niezabezpieczonym kodzie
    test_payload = "admin'"
    
    # Dane do wysłania w formularzu
    payload_data = {
        login_field: test_payload,
        password_field: "test_password_123" 
    }

    print(f"[*] Testowanie URL: {url}")
    print(f"[*] Wysłany login: {test_payload}")

    try:
        # Wykonanie żądania POST
        response = requests.post(url, data=payload_data, timeout=5)

        # Analiza odpowiedzi
        # 1. Sprawdzenie kodu statusu HTTP
        if response.status_code == 500:
            print(f"[!] OSTRZEŻENIE: Serwer zwrócił błąd 500. Może to oznaczać błąd bazy danych (podatność SQLi).")
        
        # 2. Szukanie typowych komunikatów błędów SQL w treści strony
        # To są przykładowe komunikaty zwracane przez różne silniki baz danych
        error_signatures = [
            "You have an error in your SQL syntax",
            "Warning: mysql_",
            "Unclosed quotation mark",
            "SQLServer JDBC Driver",
            "ORA-00933",  # Oracle
            "SQLite3::SQLException"
        ]

        is_vulnerable = False
        for signature in error_signatures:
            if signature.lower() in response.text.lower():
                print(f"[!] KRYTYCZNE: Znaleziono sygnaturę błędu SQL: '{signature}'")
                is_vulnerable = True
                break

        if not is_vulnerable and response.status_code != 500:
            print("[+] Wygląda na to, że aplikacja obsłużyła znak specjalny poprawnie (brak widocznych błędów SQL).")
            print("    Uwaga: To nie gwarantuje 100% bezpieczeństwa (np. w przypadku Blind SQLi).")

    except requests.exceptions.RequestException as e:
        print(f"[-] Błąd połączenia: {e}")

# --- KONFIGURACJA ---
# Podmień poniższe wartości na swoje
TARGET_URL = "https://macnuggetnet.pl/login"  # Adres Twojej strony logowania
USER_FIELD_NAME = "username"                  # Nazwa pola input w HTML (name="...")
PASS_FIELD_NAME = "password"                  # Nazwa pola hasła w HTML

if __name__ == "__main__":
    test_sql_injection_vulnerability(TARGET_URL, USER_FIELD_NAME, PASS_FIELD_NAME)
