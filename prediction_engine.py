import firebase_admin
from firebase_admin import credentials, db
import time

# Initialize Firebase Admin
cred = credentials.Certificate("esptest.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://esp32-testproject-a461b-default-rtdb.firebaseio.com'
})

print("⚡ JanRakshak Prediction Engine Running [TESTING MODE]...")

BASELINE_ANGLES = {}
ZONES = ['esp32-zone-1', 'esp32-zone-2', 'esp32-zone-3', 'esp32-zone-4']

# Thresholds
TILT_NOISE_THRESHOLD = 0.5     # Trigger movements > 0.5 degrees
WATER_NOISE_THRESHOLD = 5.0    # Trigger water values > 5
IDLE_DISTANCE_CM = 280.0       # Standard baseline distance

def safe_float(val, default=0.0):
    """Safely parse float values from JSON to handle None or invalid strings."""
    if val is None:
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def calculate_risk(zone_key, sensors):
    global BASELINE_ANGLES

    if not sensors or not isinstance(sensors, dict):
        return {
            "activeSource": "OFFLINE",
            "calamityType": "OFFLINE: Primary and Backup Nodes Unreachable",
            "floodRisk": 0.0,
            "landslideRisk": 0.0,
            "level": "Gray alert",
            "recommendation": "Inspect Sensor Node Power and Connectivity",
            "riskScore": 0.0
        }

    # Standardize Pressure to Pa
    if 'pressure_Pa' in sensors:
        pressure = safe_float(sensors.get('pressure_Pa'), 101325.0)
    elif 'pressure_hPa' in sensors:
        pressure = safe_float(sensors.get('pressure_hPa'), 1013.25) * 100.0
    elif 'pressure' in sensors:
        p_raw = safe_float(sensors.get('pressure'), 101325.0)
        pressure = p_raw * 100.0 if p_raw < 2000.0 else p_raw  # Auto-detect hPa vs Pa
    else:
        pressure = 101325.0

    humidity = safe_float(sensors.get('humidity_pct'), 0.0)
    
    # Water parsing
    raw_water = safe_float(sensors.get('water_level', sensors.get('waterLevel')), 0.0)
    water = raw_water if raw_water > WATER_NOISE_THRESHOLD else 0.0

    has_tilt = ('pitch' in sensors) and ('roll' in sensors)
    raw_pitch = safe_float(sensors.get('pitch'), 0.0)
    raw_roll = safe_float(sensors.get('roll'), 0.0)
    raw_yaw = safe_float(sensors.get('yaw'), 0.0)
    
    has_distance = 'distance_cm' in sensors
    distance = safe_float(sensors.get('distance_cm'), IDLE_DISTANCE_CM)

    # Baseline calibration initialization or recalibration trigger
    should_recalibrate = sensors.get('recalibrate', False)
    if zone_key not in BASELINE_ANGLES or should_recalibrate:
        BASELINE_ANGLES[zone_key] = {
            'pitch': raw_pitch, 
            'roll': raw_roll, 
            'yaw': raw_yaw,
            'pressure': pressure
        }

    base = BASELINE_ANGLES[zone_key]

   # --- Landslide Risk Logic ---
    if has_tilt:
        pitch_diff = abs(raw_pitch - base['pitch'])
        roll_diff = abs(raw_roll - base['roll'])
        
        # We completely ignore yaw_diff here to prevent infinite gyro drift

        # Filter noise
        pitch_diff = pitch_diff if pitch_diff > TILT_NOISE_THRESHOLD else 0.0
        roll_diff = roll_diff if roll_diff > TILT_NOISE_THRESHOLD else 0.0

        # Calculate deviation using only Pitch and Roll
        tilt_deviation = (pitch_diff + roll_diff) / 2.0
        
        # 10 degrees total average deviation yields 100% tilt risk
        tilt_score = min(100.0, (tilt_deviation / 10.0) * 100.0)
    else:
        tilt_score = 0.0

    water_score = min(100.0, (water / 500.0) * 100.0) if water > 0 else 0.0
    landslide_score = min(100.0, (tilt_score * 0.7) + (water_score * 0.3))

    # --- Flood Risk Logic ---
    if has_distance and distance < (IDLE_DISTANCE_CM - 5.0):
        water_height_score = min(100.0, ((IDLE_DISTANCE_CM - distance) / IDLE_DISTANCE_CM) * 100.0)
    else:
        water_height_score = 0.0

    pressure_drop = max(0.0, base['pressure'] - pressure)
    storm_score = min(100.0, (pressure_drop / 500.0) * 100.0) if pressure < 99000.0 else 0.0
    humidity_score = min(100.0, max(0.0, (humidity - 80.0) * 5.0)) if humidity > 80.0 else 0.0

    flood_score = min(100.0, (water_height_score * 0.4) + (water_score * 0.3) + (storm_score * 0.2) + (humidity_score * 0.1))
    max_score = max(landslide_score, flood_score)

    # Categorization
    if max_score > 75.0:
        level, calamity_type = "Red alert", "HIGH RISK: Ground Displacement & Severe Surge"
        recommendation = "IMMEDIATE EVACUATION RECOMMENDED FOR DOWNSTREAM ZONES"
    elif max_score > 45.0:
        level, calamity_type = "Orange alert", "MODERATE RISK: Weather / Slope Instability"
        recommendation = "Issue Warning & Alert Emergency Responders"
    elif max_score > 25.0:
        level, calamity_type = "Yellow alert", "LOW RISK: Minor Environmental Fluctuation"
        recommendation = "Maintain Automated Surveillance"
    else:
        level, calamity_type = "Green alert", "SAFE: All Metrics Normal & Ground Stable"
        recommendation = "No Hazard Detected. Continuous Monitoring Active."

    return {
        "activeSource": "PRIMARY",
        "calamityType": calamity_type,
        "floodRisk": round(flood_score, 1),
        "landslideRisk": round(landslide_score, 1),
        "level": level,
        "recommendation": recommendation,
        "riskScore": round(max_score, 1)
    }

def process_zones():
    for zone in ZONES:
        primary = db.reference(f'/{zone}').get()
        backup = db.reference(f'/{zone}-backup').get()

        sensors = None
        source = "OFFLINE"

        if primary and isinstance(primary, dict) and 'sensors' in primary:
            sensors = primary['sensors']
            source = "PRIMARY"
        elif backup and isinstance(backup, dict) and 'sensors' in backup:
            sensors = backup['sensors']
            source = "BACKUP"

        pred = calculate_risk(zone, sensors)
        if sensors:
            pred["activeSource"] = source

        # Write output back to Firebase
        db.reference(f'/predictions/{zone}').set(pred)
        
        if zone == 'esp32-zone-1':
            print(f"📊 [Zone 1 Test] Score: {pred['riskScore']}% | Landslide: {pred['landslideRisk']}% | Flood: {pred['floodRisk']}%")

if __name__ == "__main__":
    while True:
        try:
            process_zones()
        except Exception as e:
            print(f"Error executing loop: {e}")
        time.sleep(1)