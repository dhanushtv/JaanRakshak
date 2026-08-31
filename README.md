# JaanRakshak – Real-Time IoT & AI Disaster Intelligence Grid

> **InnoHack 2.0 Track:** IoT / Drone / Robotics  
> **Team Name:** Choki Choki[cite: 1]  
> **Target Region:** Wayanad, Kerala (High-risk slope failure & flash flood corridors)[cite: 1]

---

## 📌 Project Overview

**JaanRakshak** is an automated, real-time disaster warning network that bridges field-deployed IoT sensors, real-time cloud sync, and server-side machine learning to mitigate sudden landslides and flash floods[cite: 1]. 

Unlike traditional macro-level weather forecasts, JaanRakshak captures localized, micro-terrain environmental changes at the precise points where hazards originate (riverbanks and steep mountain slopes)[cite: 1]. It continuously analyzes physical parameters, calculates risk scores, and routes instant geo-fenced alerts to nearby residents while giving emergency agencies a live tactical command interface[cite: 1].

---

## 🛠️ Key Features

* **Hyper-Local IoT Telemetry:** Sensor nodes monitor real-time atmospheric pressure, temperature, humidity, water level proximity, and structural pitch/roll[cite: 1].
* **Predictive AI Risk Engine:** Server-side Python ML algorithms continuously evaluate multi-sensor streams to compute immediate calamity probabilities[cite: 1].
* **Dynamic Hazard Navigation:** Uses live danger data to calculate and update safe evacuation routes, steering evacuees away from flooded bridges and damaged roads[cite: 1].
* **Dual Interface System:**
  * **Native Mobile App:** Tailored for local settlers and first responders with immediate alert feeds, dynamic navigation, household safety action packs, and direct family SOS tracking[cite: 1].
  * **Web Command Center:** Designed for firefighters, police, and disaster management officials with live telemetry streams, spatial risk maps, and triage queue management[cite: 1].
* **Crowdsourced Intelligence & Mutual Aid:** Empowers citizens to post unverified condition reports, send SOS help calls, and coordinate local ration or medicine distribution during relief operations[cite: 1].
* **Offline Mesh Network Fallback:** Integrates peer-to-peer (BLE / Wi-Fi Direct / ESP-NOW) communication protocols so app users can transmit emergency messages even when cellular towers fail[cite: 1].

---

## 🏗️ System Architecture & Workflow



┌───────────────────────────┐
│     ESP32 Field Nodes     │  (Sensory Telemetry: BMP280, Ultrasonic, Pitch/Roll)
└─────────────┬─────────────┘
│  (Wi-Fi / Cellular Sync)
▼
┌───────────────────────────┐
│ Firebase Realtime Database│  (Cloud Telemetry & State Synchronization)
└─────────────┬─────────────┘
│
▼
┌───────────────────────────┐
│   Python ML Risk Engine   │  (Data Normalization & Hazard Risk Score Inference)
└──────┬─────────────────┬──┘
│                 │
▼                 ▼
┌──────────────┐  ┌───────────────────────────────┐
│  Mobile App  │  │ Web Command Center Dashboard  │
│ (Civilian)   │  │ (First Responders & Authorities)│
└──────────────┘  └───────────────────────────────┘


1. **Hardware Layer:** ESP32 microcontrollers deployed in critical risk zones stream continuous environmental metrics to Firebase[cite: 1].
2. **Predictive Layer:** Server-side Python scripts process incoming payload streams, normalize disparate sensor data, and run risk algorithms[cite: 1].
3. **Dispatch Layer:** Calculated risk scores auto-trigger geo-fenced push notifications to residents and update tactical base relocation maps for rescue squads[cite: 1].

---

## 🧰 Tech Stack

* **Hardware & Firmware:** ESP32 DevKit Modules, BMP280/BME280 Sensors, Ultrasonic Distance Sensors, Pitch/Roll Accelerometers, Arduino IDE (C/C++), Firebase ESP Client Library[cite: 1].
* **Backend & Cloud Services:** Google Firebase Realtime Database, Python 3 (Data processing, NumPy, Scikit-Learn)[cite: 1].
* **Web Command Center:** HTML5, CSS3, JavaScript, Leaflet OpenStreetMap Engine, OSRM Routing Engine[cite: 1].
* **Mobile Application:** JavaScript / XML framework packaged in a native Android shell[cite: 1].

---

## 👥 Team Members (Team Choki Choki)

| Name | Reg Number | Core Responsibilities |
| :--- | :--- | :--- |
| **Aditya Amol Dhepe** | 24BEL0044 | Mobile App UI Design & Conceptual Ideation[cite: 1] |
| **TV Dhanush** | 24BEL025 | Command Dashboard Design, ML Integration & System Debugging[cite: 1] |
| **Ephraim Chacko John**| 24BEL0068 | Microcontroller Firmware Coding & Sensor Circuitry[cite: 1] |
| **Sarvesh S V** | 24BEL0046 | App UI/UX Debugging, Presentation & Documentation[cite: 1] |

---

## 📚 References & Acknowledgments

1. Geological Survey of India & Nature Research regarding the Wayanad landslide and debris flow events[cite: 1].
2. [Google Firebase Documentation](https://firebase.google.com/docs)[cite: 1]
3. [Arduino ESP32 Core Library](https://github.com/espressif/arduino-esp32)[cite: 1]

```
