"""
enviar_notificacion.py
──────────────────────
Script para enviar notificaciones push a través de la API REST de OneSignal.

IMPORTANTE:
  - NO se usa el parámetro "url" para evitar que se abra el navegador.
  - Se usa el parámetro "data" para enviar datos ocultos que la app puede leer.

Uso:
  python enviar_notificacion.py
"""

import requests
import json

# ─── Configuración ────────────────────────────────────────────────────────────
ONESIGNAL_APP_ID = "8123fc88-aea9-4d85-9a36-8be4248fd004"
ONESIGNAL_REST_API_KEY = "os_v2_app_qer7zcfovfgylgrwrpscjd6qatldfjf6ende2cv4t3fint5zfki5vr3nphph2s4xfr4ktc7be7g4ucry2cc4driggorwogpata5ybuq"  # Reemplazar con tu clave real
# ──────────────────────────────────────────────────────────────────────────────

def enviar_notificacion():
    """Envía una notificación push con datos ocultos (sin abrir navegador)."""

    url = "https://api.onesignal.com/notifications"

    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": f"Basic {ONESIGNAL_REST_API_KEY}",
    }

    payload = {
        "app_id": ONESIGNAL_APP_ID,

        # Audiencia: enviar a todos los suscriptores
        "included_segments": ["All"],

        # Contenido visible de la notificación
        "headings": {"en": "Nueva Actualización"},
        "contents": {"en": "Se ha registrado una nueva campaña de monitoreo."},

        # ✅ Datos ocultos que la app recibe al tocar la notificación.
        # NO usar "url" aquí, porque eso fuerza la apertura del navegador.
        "data": {
            "pantalla": "notificaciones",
            "id_campana": "12345",
            "Mascota": "Gato",
            "id_usuario": "12345",
            "id_notificacion": "12345",
           "fecha": "2022-01-01" 
        },
    }

    response = requests.post(url, headers=headers, data=json.dumps(payload))

    print(f"Status Code: {response.status_code}")
    print(f"Response:    {response.json()}")


if __name__ == "__main__":
    enviar_notificacion()
