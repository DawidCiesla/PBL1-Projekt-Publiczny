# MySQL Automated Backups

## Konfiguracja

System automatycznych backupów MySQL z 31-dniową rotacją.

### Harmonogram
- **Częstotliwość**: Codziennie o 2:00 AM
- **Retencja**: 31 dni (backupy starsze niż 31 dni są automatycznie usuwane)
- **Format**: `iot_db_backup_YYYYMMDD_HHMMSS.sql.gz` (kompresja gzip)
- **Lokalizacja**: `./mysql/backups/`

### Ręczne uruchomienie backupu

```bash
cd ~/PBL1_Projekt/Serwer_vps/Glowna_aplikacja_serwerowa
./backup_mysql.sh
```

### Przywracanie z backupu

#### 1. Wyświetl dostępne backupy
```bash
ls -lh mysql/backups/*.sql.gz
```

#### 2. Przywróć wybrany backup
```bash
# Rozpakuj backup
gunzip -c mysql/backups/iot_db_backup_YYYYMMDD_HHMMSS.sql.gz > restore.sql

# Przywróć do bazy danych
docker exec -i mysql mysql -uroot -p'StrongP@ssw0rd2026_IoT_Secure' < restore.sql

# Usuń tymczasowy plik
rm restore.sql
```

#### 3. Przywracanie bezpośrednio (bez rozpakowywania)
```bash
gunzip -c mysql/backups/iot_db_backup_YYYYMMDD_HHMMSS.sql.gz | \
    docker exec -i mysql mysql -uroot -p'StrongP@ssw0rd2026_IoT_Secure'
```

### Weryfikacja cron job

Sprawdź czy zadanie jest aktywne:
```bash
crontab -l | grep backup_mysql
```

### Monitorowanie

Sprawdź logi backupów:
```bash
tail -f mysql/backups/backup.log
```

### Zawartość backupu

Backup zawiera:
- ✅ Wszystkie tabele z bazy \`iot_db\`
- ✅ Procedury składowane (routines)
- ✅ Triggery
- ✅ Eventy
- ✅ Dane w trybie transakcyjnym (--single-transaction)

### Rozwiązywanie problemów

#### Brak backupów
1. Sprawdź czy cron działa: \`sudo systemctl status cron\`
2. Sprawdź uprawnienia: \`chmod +x backup_mysql.sh\`
3. Sprawdź logi: \`cat mysql/backups/backup.log\`

#### Błąd hasła MySQL
Jeśli zmieniłeś hasło root, zaktualizuj \`MYSQL_ROOT_PASSWORD\` w \`backup_mysql.sh\`

### Statystyki

```bash
# Liczba backupów
ls -1 mysql/backups/*.sql.gz | wc -l

# Rozmiar wszystkich backupów
du -sh mysql/backups/

# Najstarszy backup
ls -lt mysql/backups/*.sql.gz | tail -1
```
