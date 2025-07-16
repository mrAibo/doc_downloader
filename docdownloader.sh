#!/bin/bash
# Verwendung: ./script.sh file1.txt file2.txt ...

PASSWD="<PASSWD>"
SERVER_PORT=8001
HTML_FILE="index.html"
CLEANUP_FILE=".cleanup"
BASE_URL="http://archndsp.aoknds.aok:7150/cs?get&pVersion=0045&contRep=RA&docId"

# Prüfe 7z Installation
if ! command -v 7z &> /dev/null; then
  echo "Fehler: 7z nicht gefunden. Bitte installieren: p7zip-full"
  exit 1
fi

# Prüfe curl Installation
if ! command -v curl &> /dev/null; then
  echo "Warnung: curl nicht gefunden, verwende wget. Für bessere Performance installiere curl."
  USE_WGET=1
else
  USE_WGET=0
fi

# CPU-Nutzung
NCPU=$(nproc)
MAX_PARALLEL=$((NCPU * 4))  # Erhöht für I/O-bound Operationen
MAX_COMPRESSION_THREADS=$NCPU

# HTML-Template
cat > "$HTML_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Archiv Download Portal</title>
<style>
  :root {
    --primary: #4f46e5;
    --primary-dark: #4338ca;
    --danger: #dc2626;
    --danger-dark: #b91c1c;
    --bg: #f8fafc;
    --bg-dark: #0f172a;
    --text: #1e293b;
    --text-dark: #e2e8f0;
    --card-bg: #ffffff;
    --card-bg-dark: #1e293b;
    --border: #e2e8f0;
    --border-dark: #334155;
    --success: #10b981;
    --success-dark: #059669;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Inter', system-ui, -apple-system, sans-serif;
    line-height: 1.6;
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
    background: var(--bg);
    color: var(--text);
    transition: background-color 0.3s, color 0.3s;
    position: relative;
    min-height: 100vh;
  }
  body.dark {
    --bg: var(--bg-dark);
    --text: var(--text-dark);
    --card-bg: var(--card-bg-dark);
    --border: var(--border-dark);
  }
  .theme-toggle {
    position: fixed;
    top: 1rem;
    right: 1rem;
    background: none;
    border: 2px solid var(--border);
    color: var(--text);
    padding: 0.5rem;
    border-radius: 50%;
    cursor: pointer;
    transition: all 0.3s;
  }
  .theme-toggle:hover {
    transform: rotate(45deg);
  }
  h2 {
    color: var(--text);
    margin-bottom: 2rem;
    text-align: center;
    font-size: 2.5rem;
    font-weight: 800;
    letter-spacing: -0.025em;
  }
  .file-item {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 12px;
    margin: 1rem 0;
    padding: 1.5rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    transition: all 0.3s;
    position: relative;
    overflow: hidden;
  }
  .file-item::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    width: 4px;
    height: 100%;
    background: var(--primary);
    transform: scaleY(0);
    transition: transform 0.3s;
  }
  .file-item:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 16px rgba(0,0,0,0.1);
  }
  .file-item:hover::before {
    transform: scaleY(1);
  }
  .file-item a {
    color: var(--primary);
    text-decoration: none;
    font-weight: 600;
    font-size: 1.1rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  .file-item a::before {
    content: '📁';
  }
  .file-item a:hover {
    color: var(--primary-dark);
  }
  .actions {
    display: flex;
    gap: 1rem;
    align-items: center;
  }
  button {
    background: var(--danger);
    color: white;
    border: none;
    padding: 0.75rem 1.5rem;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 600;
    font-size: 0.9rem;
    transition: all 0.3s;
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  button:hover {
    background: var(--danger-dark);
    transform: scale(1.05);
  }
  button:active {
    transform: scale(0.95);
  }
  button.download-all {
    background: var(--success);
    margin: 1rem auto;
    padding: 1rem 2rem;
    font-size: 1.1rem;
  }
  button.download-all:hover {
    background: var(--success-dark);
  }
  hr {
    margin: 2rem 0;
    border: none;
    border-top: 1px solid var(--border);
  }
  #shutdown-form {
    text-align: center;
  }
  #shutdown-form button {
    background: var(--primary);
    font-size: 1.1rem;
    padding: 1rem 2rem;
  }
  #shutdown-form button:hover {
    background: var(--primary-dark);
  }
  .loading {
    text-align: center;
    padding: 2rem;
    color: var(--text);
    font-size: 1.1rem;
  }
  .loading::after {
    content: '';
    display: inline-block;
    width: 1em;
    height: 1em;
    border: 2px solid var(--text);
    border-radius: 50%;
    border-top-color: transparent;
    animation: spin 1s linear infinite;
    margin-left: 0.5rem;
    vertical-align: middle;
  }
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
  .empty-state {
    text-align: center;
    color: var(--text);
    padding: 3rem;
    font-size: 1.1rem;
  }
  .toast {
    position: fixed;
    bottom: 2rem;
    left: 50%;
    transform: translateX(-50%);
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1rem 2rem;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    display: none;
    animation: slideUp 0.3s ease;
  }
  @keyframes slideUp {
    from { transform: translate(-50%, 100%); opacity: 0; }
    to { transform: translate(-50%, 0); opacity: 1; }
  }
  .footer-note {
    position: fixed;
    bottom: 1rem;
    right: 1rem;
    font-size: 0.8rem;
    color: var(--text);
    opacity: 0.7;
    text-align: right;
    max-width: 200px;
  }
  @media (max-width: 768px) {
    body { padding: 1rem; }
    h2 { font-size: 2rem; }
    .file-item { 
      flex-direction: column; 
      gap: 1rem; 
      text-align: center; 
      padding: 1.25rem;
    }
    .actions { justify-content: center; }
    .theme-toggle { 
      top: auto;
      bottom: 1rem;
      right: 1rem;
    }
    .footer-note {
      bottom: 4rem;
      right: 1rem;
      font-size: 0.7rem;
    }
  }
</style>
</head>
<body>
  <button class="theme-toggle" title="Farbschema wechseln">🌓</button>
  <h2>Archiv Download Portal</h2>
  <div id="file-list" class="loading">Lade Dateien...</div>
  <div id="download-all-container" style="text-align: center; display: none;">
    <button class="download-all" id="download-all-btn">📥 Alle Dateien herunterladen</button>
  </div>
  <hr>
  <form id="shutdown-form" action="/shutdown" method="post">
    <button type="submit">Server stoppen und aufräumen</button>
  </form>
  <div id="toast" class="toast"></div>
  <div class="footer-note">Diese Seite wurde für Sie vom DMS-Team bereitgestellt.</div>
  <script>
    const body = document.body;
    const themeToggle = document.querySelector('.theme-toggle');
    const toast = document.getElementById('toast');
    const downloadAllContainer = document.getElementById('download-all-container');
    const downloadAllBtn = document.getElementById('download-all-btn');

    // Theme Toggle
    const isDark = localStorage.getItem('dark-mode') === 'true';
    if (isDark) body.classList.add('dark');

    themeToggle.addEventListener('click', () => {
      body.classList.toggle('dark');
      localStorage.setItem('dark-mode', body.classList.contains('dark'));
    });

    // Toast Notification
    function showToast(message, duration = 3000) {
      toast.textContent = message;
      toast.style.display = 'block';
      setTimeout(() => {
        toast.style.display = 'none';
      }, duration);
    }

    // File Loading mit Cache-Optimierung
    let lastFileList = [];
    let isLoading = false;
    
    async function loadFiles() {
      // Verhindere parallele Anfragen
      if (isLoading) return;
      isLoading = true;
      
      const fileList = document.getElementById('file-list');
      
      try {
        const response = await fetch('/list?_=' + Date.now()); // Cache-Busting
        const files = await response.json();
        
        // Prüfe, ob sich die Dateiliste geändert hat
        if (JSON.stringify(files) === JSON.stringify(lastFileList)) {
          isLoading = false;
          return; // Keine Änderung, kein DOM-Update nötig
        }
        
        lastFileList = [...files]; // Speichere für späteren Vergleich
        
        if (files.length === 0) {
          fileList.className = 'empty-state';
          fileList.innerHTML = 'Keine Archive verfügbar';
          downloadAllContainer.style.display = 'none';
          isLoading = false;
          return;
        }

        // Behalte die aktuelle Klasse bei, entferne nur 'loading' wenn vorhanden
        fileList.className = fileList.className.replace('loading', '').trim();
        
        // Zeige "Alle herunterladen" Button, wenn Dateien vorhanden sind
        downloadAllContainer.style.display = 'block';
        
        // Erstelle neues HTML ohne die Seite zu "zittern"
        const newHTML = files.map(file => `
          <div class="file-item">
            <a href="/download/${file}" title="${file} herunterladen">${file}</a>
            <div class="actions">
              <form action="/delete" method="post" style="margin: 0;">
                <input type="hidden" name="file" value="${file}">
                <button type="submit" title="${file} löschen">🗑️ Löschen</button>
              </form>
            </div>
          </div>
        `).join('');
        
        // Nur DOM aktualisieren, wenn sich der Inhalt tatsächlich geändert hat
        if (fileList.innerHTML !== newHTML) {
          fileList.innerHTML = newHTML;
          
          // Add event listeners for delete actions
          document.querySelectorAll('form[action="/delete"]').forEach(form => {
            form.addEventListener('submit', async (e) => {
              e.preventDefault();
              const fileName = form.querySelector('input[name="file"]').value;
              await fetch('/delete', {
                method: 'POST',
                body: new URLSearchParams(new FormData(form))
              });
              showToast(`${fileName} wurde gelöscht`);
              loadFiles();
            });
          });
        }
      } catch (error) {
        console.error('Fehler beim Laden der Dateien:', error);
        if (!fileList.className.includes('empty-state')) {
          fileList.className = 'empty-state';
          fileList.innerHTML = 'Fehler beim Laden der Dateien';
        }
      } finally {
        isLoading = false;
      }
    }

    // Download All Functionality
    downloadAllBtn.addEventListener('click', async () => {
      if (lastFileList.length === 0) {
        showToast('Keine Dateien zum Herunterladen verfügbar');
        return;
      }
      
      showToast('Erstelle ZIP mit allen Dateien...');
      
      // Direkter Download aller Dateien als ZIP
      window.location.href = '/download-all';
    });

    // Initial load and refresh
    loadFiles();
    
    // Reduziere die Aktualisierungsrate auf 10 Sekunden
    setInterval(loadFiles, 10000);

    // Shutdown form handling
    document.getElementById('shutdown-form').addEventListener('submit', () => {
      showToast('Server wird heruntergefahren...');
    });
  </script>
</body>
</html>
EOF

# Download-Funktion mit curl oder wget
download_file() {
  local DOCID=$1
  local DIR=$2
  local OUTPUT="${DIR}/${DOCID}.pdf"
  local TEMP_OUTPUT="${DIR}/temp_${DOCID}.pdf"
  local URL="${BASE_URL}=${DOCID}&compId=data"
  
  if [ $USE_WGET -eq 1 ]; then
    if wget --timeout=15 --tries=2 -q -O "$TEMP_OUTPUT" "$URL"; then
      mv "$TEMP_OUTPUT" "$OUTPUT"
      return 0
    fi
  else
    # curl ist als wget und hat bessere Fehlerbehandlung
    if curl -s -f -m 15 --retry 2 -o "$TEMP_OUTPUT" "$URL"; then
      mv "$TEMP_OUTPUT" "$OUTPUT"
      return 0
    fi
  fi
  
  return 1
}

#  Verarbeitung mit Chunking für bessere Parallelisierung
process_file() {
  local INPUT_FILE=$1
  local DIR=$(head -n1 "$INPUT_FILE")
  local DOCIDS=$(tail -n +2 "$INPUT_FILE")
  local TEMP_ERROR_LOG="${DIR}_errors.tmp"
  local RETRY_LOG="${DIR}_retry.tmp"
  local MAX_RETRIES=5  # mehr Zuverlässigkeit
  local CHUNK_SIZE=50  # Verarbeite Dokumente in Chunks
  
  mkdir -p "$DIR"
  > "$TEMP_ERROR_LOG"
  > "$RETRY_LOG"
  
  # Zähle Dokumente für Fortschrittsanzeige
  local TOTAL_DOCS=$(echo "$DOCIDS" | wc -l)
  local PROCESSED=0
  
  # Verarbeite in Chunks
  echo "$DOCIDS" | while read -r DOCID || [[ -n "$DOCID" ]]; do
    # Download im Hintergrund mit Semaphore für Parallelisierung
    (
      if ! download_file "$DOCID" "$DIR"; then
        echo "$DOCID" >> "$RETRY_LOG"
      fi
    ) &
    
    # Begrenze Anzahl paralleler Prozesse
    if [[ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]]; then
      wait -n  # Warte auf Beendigung eines Jobs
    fi
    
    # Aktualisiere und zeige Fortschritt
    PROCESSED=$((PROCESSED + 1))
    if [[ $((PROCESSED % 10)) -eq 0 || $PROCESSED -eq $TOTAL_DOCS ]]; then
      echo -ne "Verarbeite $DIR: $PROCESSED/$TOTAL_DOCS ($(( PROCESSED * 100 / TOTAL_DOCS ))%)\r"
    fi
  done
  
  # Warte auf Fertigstellung aller Downloads
  wait
  echo -e "Verarbeite $DIR: $TOTAL_DOCS/$TOTAL_DOCS (100%) - Abgeschlossen"
  
  # Retry-Logik für fehlgeschlagene Downloads
  if [ -s "$RETRY_LOG" ]; then
    local RETRY_COUNT=1
    local RETRY_DOCS=$(cat "$RETRY_LOG" | wc -l)
    
    echo "Versuche erneut, $RETRY_DOCS fehlgeschlagene Downloads zu verarbeiten..."
    
    while [ $RETRY_COUNT -le $MAX_RETRIES ] && [ -s "$RETRY_LOG" ]; do
      echo "Wiederholungsversuch $RETRY_COUNT von $MAX_RETRIES für $DIR..."
      
      # Temporäre Datei für den nächsten Versuch
      local NEXT_RETRY="${DIR}_retry_next.tmp"
      > "$NEXT_RETRY"
      
      # Verarbeite fehlgeschlagene DocIDs mit längeren Timeouts
      cat "$RETRY_LOG" | while read -r DOCID || [[ -n "$DOCID" ]]; do
        echo "Wiederhole Download für $DOCID in $DIR..."
        # Versuche mit längeren Timeouts und mehr Retries
        if ! curl -s -f -m 60 --retry 5 --retry-delay 3 -o "${DIR}/${DOCID}.pdf" "${BASE_URL}=${DOCID}&compId=data"; then
          echo "$DOCID" >> "$NEXT_RETRY"
          echo "Fehlgeschlagen: $DOCID"
        else
          echo "Erfolgreich: $DOCID"
        fi
        # Kurze Pause zwischen Downloads
        sleep 1
      done
      
      # Retry-Log für den nächsten Durchlauf
      mv "$NEXT_RETRY" "$RETRY_LOG"
      RETRY_COUNT=$((RETRY_COUNT + 1))
      
      # Fortschrittanzeige
      local REMAINING=$(cat "$RETRY_LOG" | wc -l)
      local SUCCESS=$((RETRY_DOCS - REMAINING))
      echo "Wiederholungsversuch $RETRY_COUNT abgeschlossen: $SUCCESS von $RETRY_DOCS erfolgreich, $REMAINING verbleibend."
      
      # Wenn alle Downloads erfolgreich waren, beende die Schleife
      if [ ! -s "$RETRY_LOG" ]; then
        echo "Alle Downloads für $DIR erfolgreich abgeschlossen!"
        break
      fi
      
      # Längere Pause zwischen den Versuchen
      sleep 5
    done
    
    # Nach allen Versuchen verbleibende Fehler protokollieren
    if [ -s "$RETRY_LOG" ]; then
      echo "WARNUNG: Fehler beim Download folgender DocIDs in $DIR nach $MAX_RETRIES Versuchen:"
      cat "$RETRY_LOG"
      echo "Diese DocIDs werden in die Fehlerliste aufgenommen."
      cat "$RETRY_LOG" >> "$TEMP_ERROR_LOG"
    fi
  fi
  
  # Prüfe, ob alle Dokumente heruntergeladen wurden
  local DOWNLOADED=$(find "$DIR" -name "*.pdf" | wc -l)
  local EXPECTED=$TOTAL_DOCS
  local FAILED=$(cat "$TEMP_ERROR_LOG" 2>/dev/null | wc -l)
  
  echo "Statistik für $DIR:"
  echo "- Erwartet: $EXPECTED Dokumente"
  echo "- Heruntergeladen: $DOWNLOADED Dokumente"
  echo "- Fehlgeschlagen: $FAILED Dokumente"
  
  # Prüfe auf fehlende Dokumente
  if [ $DOWNLOADED -lt $((EXPECTED - FAILED)) ]; then
    echo "WARNUNG: Es fehlen Dokumente in $DIR!"
    echo "Prüfe auf fehlende Dokumente..."
    
    # Erstelle temporäre Datei mit allen erwarteten DocIDs
    local ALL_DOCIDS_FILE=$(mktemp)
    echo "$DOCIDS" > "$ALL_DOCIDS_FILE"
    
    # Erstelle temporäre Datei mit allen heruntergeladenen DocIDs
    local DOWNLOADED_DOCIDS_FILE=$(mktemp)
    find "$DIR" -name "*.pdf" | sed "s|$DIR/||" | sed "s|\.pdf$||" > "$DOWNLOADED_DOCIDS_FILE"
    
    # Finde fehlende DocIDs
    local MISSING_DOCIDS_FILE=$(mktemp)
    grep -v -f "$DOWNLOADED_DOCIDS_FILE" "$ALL_DOCIDS_FILE" > "$MISSING_DOCIDS_FILE"
    
    # Versuche fehlende Dokumente herunterzuladen
    if [ -s "$MISSING_DOCIDS_FILE" ]; then
      local MISSING_COUNT=$(cat "$MISSING_DOCIDS_FILE" | wc -l)
      echo "Es fehlen $MISSING_COUNT Dokumente. Versuche erneut herunterzuladen..."
      
      cat "$MISSING_DOCIDS_FILE" | while read -r DOCID || [[ -n "$DOCID" ]]; do
        if [ -f "${DIR}/${DOCID}.pdf" ]; then
          echo "Datei ${DOCID}.pdf existiert bereits, überspringe."
          continue
        fi
        
        echo "Lade fehlendes Dokument $DOCID..."
        if ! curl -s -f -m 60 --retry 5 --retry-delay 3 -o "${DIR}/${DOCID}.pdf" "${BASE_URL}=${DOCID}&compId=data"; then
          echo "$DOCID" >> "$TEMP_ERROR_LOG"
          echo "Fehlgeschlagen: $DOCID"
        else
          echo "Erfolgreich: $DOCID"
        fi
        # Kurze Pause zwischen Downloads
        sleep 1
      done
    fi
    
    # Aufräumen
    rm -f "$ALL_DOCIDS_FILE" "$DOWNLOADED_DOCIDS_FILE" "$MISSING_DOCIDS_FILE"
  fi
  
  # Aufräumen
  rm -f "$RETRY_LOG"
  
  # Fehlerbehandlung konsolidieren
  if [ -s "$TEMP_ERROR_LOG" ]; then
    echo "Fehler beim Download folgender DocIDs in $DIR:" >> download_errors.log
    cat "$TEMP_ERROR_LOG" >> download_errors.log
    FAILED=$(cat "$TEMP_ERROR_LOG" | wc -l)
    echo "Insgesamt $FAILED Dokumente konnten nicht heruntergeladen werden."
  fi
  
  # Optimierte Archivierung mit extremen Geschwindigkeitseinstellungen
  local FILE_COUNT=$(find "$DIR" -type f -name "*.pdf" | wc -l)
  if [ $FILE_COUNT -gt 0 ]; then
    echo "Komprimiere $FILE_COUNT Dateien in ${DIR}.7z"
    
    # Entferne alle temporären Dateien vor der Archivierung
    find "$DIR" -name "temp_*" -type f -delete
    
    # Ultra-schnelle 7z-Parameter:
    # -mx0: keine Kompression (nur Archivierung)
    # -mmt: Multithreading mit maximaler Anzahl Threads
    # -ms=off: Solid-Modus aus für schnellere Kompression
    7z a -mx0 -mmt=$MAX_COMPRESSION_THREADS -ms=off -p"$PASSWD" -mhe=on "${DIR}.7z" "$DIR"
    
    # Speichere die tatsächliche Anzahl der Dokumente für spätere Verwendung
    echo "$TOTAL_DOCS" > "${DIR}.count"
    echo "$FILE_COUNT" > "${DIR}.actual_count"
    
    echo "${DIR}.7z" >> "$CLEANUP_FILE"
    echo "Archivierung von $DIR abgeschlossen"
    
    # Prüfe, ob alle Dokumente archiviert wurden
    if [ $FILE_COUNT -lt $((TOTAL_DOCS - FAILED)) ]; then
      echo "WARNUNG: Nicht alle Dokumente wurden archiviert!"
      echo "Erwartet: $((TOTAL_DOCS - FAILED)), Archiviert: $FILE_COUNT"
      echo "Bitte überprüfen Sie das Archiv manuell."
    else
      echo "Alle verfügbaren Dokumente wurden erfolgreich archiviert."
    fi
  else
    echo "Keine Dateien für $DIR gefunden, überspringe Archivierung"
  fi
  
  # Verbesserte Verzeichnisbereinigung
  find "$DIR" -type f -delete  # Lösche alle Dateien
  rm -rf "$DIR"                # Dann versuche das Verzeichnis zu löschen
  rm -f "$TEMP_ERROR_LOG"      # Lösche temporäre Fehlerdatei
}

# Hauptprogramm
> "$CLEANUP_FILE"

# Verarbeite Dateien parallel, wenn mehrere Eingabedateien vorhanden sind
if [ $# -gt 1 ] && [ $NCPU -gt 1 ]; then
  echo "Starte parallele Verarbeitung von $# Dateien"
  for input_file in "$@"; do
    # Starte maximal NCPU/2 parallele Prozesse für Dateien
    process_file "$input_file" &
    if [[ $(jobs -r | wc -l) -ge $((NCPU / 2)) ]]; then
      wait -n
    fi
  done
  wait
else
  # Sequentielle Verarbeitung für einzelne Datei oder schwache CPUs
  for input_file in "$@"; do
    process_file "$input_file"
  done
fi

# Web-Server mit optimierter Konfiguration
python3 <<EOF &
import os
import json
import http.server
import socketserver
import threading
import time
import mimetypes
import zipfile
import io
import glob
from http import HTTPStatus
from functools import lru_cache

PORT = $SERVER_PORT
CLEANUP_FILE = "$CLEANUP_FILE"
HTML_FILE = "$HTML_FILE"

# Optimiere Dateiübertragung mit Pufferung
BUFFER_SIZE = 64 * 1024  # 64KB Puffer für bessere Leistung

# Cache für Dateilisten (30 Sekunden TTL)
@lru_cache(maxsize=1)
def cached_list_archives(timestamp):
    # timestamp wird ignoriert, dient nur zum Invalidieren des Caches
    return [f for f in os.listdir() if f.endswith('.7z')]

class OptimizedHandler(http.server.SimpleHTTPRequestHandler):
    # Optimiere Protokollierung
    def log_message(self, format, *args):
        # Reduziere Logging für bessere Performance
        if args[0].startswith('2') or args[0].startswith('3'):
            status_code = int(args[0])
            if 200 <= status_code < 400:
            return
        super().log_message(format, *args)
    
    def list_archives(self):
        # Verwende gecachte Liste mit aktuellem Zeitstempel
        cache_key = int(time.time()) // 30  # Invalidiere alle 30 Sekunden
        return cached_list_archives(cache_key)

    def do_GET(self):
        if self.path == '/':
            self.send_response(HTTPStatus.OK)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.send_header('Cache-Control', 'max-age=60')  # 1 Minute Cache
            self.end_headers()
            with open("$HTML_FILE", 'rb') as f:
                self.wfile.write(f.read())
        elif self.path.startswith('/list'):
            self.send_response(HTTPStatus.OK)
            self.send_header('Content-type', 'application/json')
            self.send_header('Cache-Control', 'max-age=10')  # 10 Sekunden Cache
            self.end_headers()
            self.wfile.write(json.dumps(self.list_archives()).encode())
        elif self.path.startswith('/download/'):
            file = self.path.split('/')[-1]
            if os.path.exists(file):
                file_size = os.path.getsize(file)
                self.send_response(HTTPStatus.OK)
                self.send_header('Content-type', 'application/octet-stream')
                self.send_header('Content-Disposition', f'attachment; filename="{file}"')
                self.send_header('Content-Length', str(file_size))
                self.end_headers()
                
                # Optimierte Dateiübertragung mit Pufferung
                with open(file, 'rb') as f:
                    while True:
                        buffer = f.read(BUFFER_SIZE)
                        if not buffer:
                            break
                        self.wfile.write(buffer)
            else:
                self.send_error(HTTPStatus.NOT_FOUND)
        elif self.path == '/download-all':
            # Erstelle ein ZIP mit allen 7z-Dateien
            files = self.list_archives()
            if not files:
                self.send_error(HTTPStatus.NOT_FOUND, "Keine Dateien verfügbar")
                return
                
            # Erstelle ZIP im Speicher
            zip_buffer = io.BytesIO()
            with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_STORED) as zip_file:
                for file in files:
                    if os.path.exists(file):
                        zip_file.write(file, file)
            
            # Sende ZIP als Download
            zip_buffer.seek(0)
            self.send_response(HTTPStatus.OK)
            self.send_header('Content-type', 'application/zip')
            self.send_header('Content-Disposition', 'attachment; filename="alle_archive.zip"')
            self.send_header('Content-Length', str(zip_buffer.getbuffer().nbytes))
            self.end_headers()
            self.wfile.write(zip_buffer.getvalue())
        else:
            self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self):
        if self.path == '/shutdown':
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header('Location', '/')
            self.end_headers()
            
            # Starte Shutdown in einem separaten Thread
            threading.Thread(target=self.shutdown_server).start()
        else:
            self.send_error(HTTPStatus.NOT_FOUND)
    
    def shutdown_server(self):
        print("Server wird heruntergefahren...")
        
        # Lösche alle Archive und temporäre Dateien
        if os.path.exists(CLEANUP_FILE):
            with open(CLEANUP_FILE) as f:
                for file in f:
                    file = file.strip()
                    if os.path.exists(file):
                        print(f"Lösche Archiv: {file}")
                        os.remove(file)
            os.remove(CLEANUP_FILE)
        
        # Lösche alle temporären Dateien
        print("Lösche temporäre Dateien...")
        temp_files = []
        
        # Sammle alle .count und .actual_count Dateien
        temp_files.extend(glob.glob("*.count"))
        temp_files.extend(glob.glob("*.actual_count"))
        
        # Sammle alle Retry- und Error-Logs
        temp_files.extend(glob.glob("*_retry.tmp"))
        temp_files.extend(glob.glob("*_errors.tmp"))
        
        # Lösche alle temporären Dateien
        for temp_file in temp_files:
            if os.path.exists(temp_file):
                print(f"Lösche temporäre Datei: {temp_file}")
                os.remove(temp_file)
        
        # Verzögere das Löschen der HTML-Datei und das Herunterfahren des Servers
        def delayed_shutdown():
            # Warte kurz, damit die letzte Anfrage verarbeitet werden kann
            time.sleep(2)
            
            # Lösche HTML-Datei
            if os.path.exists(HTML_FILE):
                print(f"Lösche HTML-Datei: {HTML_FILE}")
                os.remove(HTML_FILE)
            
            print("Bereinigung abgeschlossen. Server wird gestoppt.")
            self.server.shutdown()
        
        # Starte verzögerten Shutdown
        threading.Thread(target=delayed_shutdown).start()

# Optimierter TCP-Server mit schnelleren Verbindungen
class OptimizedTCPServer(socketserver.TCPServer):
    allow_reuse_address = True  # Schnellerer Neustart
    request_queue_size = 10     # Mehr gleichzeitige Verbindungen

with OptimizedTCPServer(("", PORT), OptimizedHandler) as httpd:
    print(f"Server gestartet auf Port {PORT}")
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
EOF

echo "Zugriff auf: http://$(hostname -I | awk '{print $1}'):${SERVER_PORT}"

# E-Mail senden (asynchron für schnelleren Start)
(
  SERVER_IP=$(hostname -I | awk '{print $1}')
  #EMAIL="aleksej.voronin@nds.aok.de, sven.lindt@nds.aok.de, philipp.minkus@nds.aok.de"
  EMAIL="aleksej.voronin@nds.aok.de"
  SUBJECT="Server gestartet"
  
  # Warte kurz, bis alle Archive erstellt wurden
  sleep 2
  
  # Sammle Informationen über die archivierten Dateien
  ARCHIVE_INFO=""
  TOTAL_ARCHIVES=0
  TOTAL_DOCS=0
  
  if [ -f "$CLEANUP_FILE" ]; then
    while read -r ARCHIVE_FILE; do
      if [ -f "$ARCHIVE_FILE" ]; then
        # Extrahiere Dateinamen und Größe
        ARCHIVE_NAME=$(basename "$ARCHIVE_FILE")
        ARCHIVE_SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
        
        # Extrahiere Verzeichnisnamen (ohne .7z)
        DIR_NAME="${ARCHIVE_NAME%.7z}"
        
        # Verwende die gespeicherte Anzahl der Dokumente, wenn verfügbar
        if [ -f "${DIR_NAME}.count" ]; then
          DOC_COUNT=$(cat "${DIR_NAME}.count")
        # Alternativ aus der Eingabedatei, wenn verfügbar
        elif [ -f "${DIR_NAME}.txt" ]; then
          # Zähle Zeilen in der Datei minus die erste Zeile (Verzeichnisname)
          DOC_COUNT=$(wc -l < "${DIR_NAME}.txt")
          DOC_COUNT=$((DOC_COUNT - 1))
        # Fallback: Verwende die Anzahl der Dateien im Archiv
        else
          DOC_COUNT="unbekannt"
        fi
        
        ARCHIVE_INFO="${ARCHIVE_INFO}    <tr>
      <td>${ARCHIVE_NAME}</td>
      <td>${DOC_COUNT}</td>
      <td>${ARCHIVE_SIZE}</td>
    </tr>
"
        TOTAL_ARCHIVES=$((TOTAL_ARCHIVES + 1))
        if [ "$DOC_COUNT" != "unbekannt" ]; then
          TOTAL_DOCS=$((TOTAL_DOCS + DOC_COUNT))
        fi
      fi
    done < "$CLEANUP_FILE"
  fi
  
  # Wenn keine Archive gefunden wurden
  if [ -z "$ARCHIVE_INFO" ]; then
    ARCHIVE_INFO="    <tr><td colspan='3'>Keine Archive gefunden</td></tr>"
  fi
  
  # HTML-E-Mail-Inhalt mit korrekter Kodierung und Archiv-Informationen
  HTML_EMAIL=$(cat <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; }
    .container { border: 1px solid #ddd; border-radius: 5px; padding: 20px; }
    h2 { color: #4f46e5; border-bottom: 1px solid #eee; padding-bottom: 10px; }
    h3 { color: #4f46e5; margin-top: 20px; }
    .server-link { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 15px 0; font-weight: bold; }
    .server-link a { color: #4f46e5; text-decoration: none; }
    ol { margin-left: 20px; }
    li { margin-bottom: 10px; }
    .footer { margin-top: 20px; font-size: 0.9em; color: #666; border-top: 1px solid #eee; padding-top: 10px; }
    table { width: 100%; border-collapse: collapse; margin: 15px 0; }
    th { background: #f8f9fa; text-align: left; padding: 8px; border-bottom: 2px solid #ddd; }
    td { padding: 8px; border-bottom: 1px solid #eee; }
    .summary { background: #f8f9fa; padding: 10px; border-radius: 5px; margin: 15px 0; }
  </style>
</head>
<body>
  <div class="container">
    <h2>Archiv Download Server</h2>
    <p>Der Server wurde erfolgreich gestartet und ist jetzt verfügbar.</p>
    
    <div class="server-link">
      Server-Adresse: <a href="http://${SERVER_IP}:${SERVER_PORT}">http://${SERVER_IP}:${SERVER_PORT}</a>
    </div>
    
    <h3>Bereitgestellte Archive</h3>
    <div class="summary">
      <strong>Zusammenfassung:</strong> ${TOTAL_ARCHIVES} Archive mit insgesamt ${TOTAL_DOCS} Dokumenten
    </div>
    
    <table>
      <thead>
        <tr>
          <th>Archiv</th>
          <th>Dokumente</th>
          <th>Größe</th>
        </tr>
      </thead>
      <tbody>
${ARCHIVE_INFO}
      </tbody>
    </table>
    
    <h3>Anleitung:</h3>
    <ol>
      <li>Archive können einzeln oder alle zusammen über die Webseite heruntergeladen werden.</li>
      <li>Jedes Archiv ist mit einem Passwort geschützt. Verwenden Sie das bekannte Standardpasswort.</li>
      <li>Zum Beenden klicken Sie auf <strong>'Server stoppen und aufräumen'</strong>.</li>
      <li>Alle Dateien werden nach dem Stopp automatisch gelöscht.</li>
    </ol>
    
    <div class="footer">
      <p>Dies ist eine automatisch generierte Nachricht. Bitte antworten Sie nicht auf diese E-Mail.</p>
      <p>Bei Fragen wenden Sie sich bitte an den ARGE-DMS.</p>
    </div>
  </div>
</body>
</html>
EOF
)

  # Fallback-Text für E-Mail-Clients, die kein HTML unterstützen
  TEXT_EMAIL=$(cat <<EOF
=======================================================
           ARCHIV DOWNLOAD SERVER GESTARTET
=======================================================

Der Server wurde erfolgreich gestartet und ist jetzt verfügbar.

SERVER-ADRESSE: http://${SERVER_IP}:${SERVER_PORT}

BEREITGESTELLTE ARCHIVE:
---------------------------------------------------------
Zusammenfassung: ${TOTAL_ARCHIVES} Archive mit insgesamt ${TOTAL_DOCS} Dokumenten

$([ -f "$CLEANUP_FILE" ] && while read -r ARCHIVE_FILE; do
  if [ -f "$ARCHIVE_FILE" ]; then
    ARCHIVE_NAME=$(basename "$ARCHIVE_FILE")
    # Verwende die gespeicherte Anzahl oder die Eingabedatei
    DIR_NAME="${ARCHIVE_NAME%.7z}"
    if [ -f "${DIR_NAME}.count" ]; then
      DOC_COUNT=$(cat "${DIR_NAME}.count")
    elif [ -f "${DIR_NAME}.txt" ]; then
      DOC_COUNT=$(wc -l < "${DIR_NAME}.txt")
      DOC_COUNT=$((DOC_COUNT - 1))
    else
      DOC_COUNT="unbekannt"
    fi
    SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
    echo "* $ARCHIVE_NAME: $DOC_COUNT Dokumente ($SIZE)"
  fi
done < "$CLEANUP_FILE")
---------------------------------------------------------

ANLEITUNG:
---------------------------------------------------------
1. Archive können einzeln oder alle zusammen über die 
   Webseite heruntergeladen werden
---------------------------------------------------------
2. Jedes Archiv ist mit einem Passwort geschützt. 
   Verwenden Sie das bekannte Standardpasswort
---------------------------------------------------------
3. Zum Beenden 'Server stoppen und aufräumen' klicken
---------------------------------------------------------
4. Alle Dateien werden nach dem Stopp automatisch gelöscht
---------------------------------------------------------

Dies ist eine automatisch generierte Nachricht.
Bitte antworten Sie nicht auf diese E-Mail.

Bei Fragen wenden Sie sich bitte an den ARGE-DMS.
=======================================================
EOF
)

  # Temporäre Dateien für E-Mail-Inhalte
  HTML_FILE=$(mktemp)
  
  # Speichere HTML mit korrekter UTF-8-Kodierung
  echo "$HTML_EMAIL" > "$HTML_FILE"

  # Sende E-Mail mit mutt und korrekter Kodierung
  if command -v mutt &> /dev/null; then
    mutt -e "set content_type=text/html; set send_charset=utf-8" -s "$SUBJECT" "$EMAIL" < "$HTML_FILE"
  else
    # Fallback auf einfaches mail
    echo -e "$TEXT_EMAIL" | mail -s "$SUBJECT" "$EMAIL"
  fi
  
  # Temporäre Dateien aufräumen
  rm -f "$HTML_FILE"
) &

echo "Skript erfolgreich gestartet!"
