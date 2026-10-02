import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'firebase_options.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const JanRakshakApp());
}

class JanRakshakApp extends StatelessWidget {
  const JanRakshakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JanRakshak Live Hazard Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      home: const LiveDashboardScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// Data Models
// -----------------------------------------------------------------------------

enum HazardStatus { critical, warning, citizenOnly, normal }

class ESP32NodeData {
  final String nodeId;
  final LatLng location;
  final double waterLevelCm;
  final double tempC;
  final double humidityPct;
  final double pressureHpa;
  final double accelVibration;

  ESP32NodeData({
    required this.nodeId,
    required this.location,
    required this.waterLevelCm,
    required this.tempC,
    required this.humidityPct,
    required this.pressureHpa,
    required this.accelVibration,
  });

  factory ESP32NodeData.fromMap(String key, Map<dynamic, dynamic> map) {
    final loc = map['location'] ?? {};
    final sensors = map['sensors'] ?? {};
    return ESP32NodeData(
      nodeId: map['node_id'] ?? key,
      location: LatLng(
        (loc['lat'] as num?)?.toDouble() ?? 12.9340,
        (loc['lng'] as num?)?.toDouble() ?? 79.1360,
      ),
      waterLevelCm: (sensors['water_level_cm'] as num?)?.toDouble() ?? 0.0,
      tempC: (sensors['temperature_c'] as num?)?.toDouble() ?? 0.0,
      humidityPct: (sensors['humidity_pct'] as num?)?.toDouble() ?? 0.0,
      pressureHpa: (sensors['pressure_hpa'] as num?)?.toDouble() ?? 0.0,
      accelVibration: (sensors['accel_vibration'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CitizenReport {
  final String reportId;
  final String hazardType;
  final LatLng location;
  final String description;
  final String photoUrl;

  CitizenReport({
    required this.reportId,
    required this.hazardType,
    required this.location,
    required this.description,
    required this.photoUrl,
  });

  factory CitizenReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final geo = data['location'] as GeoPoint? ?? const GeoPoint(12.9340, 79.1360);
    return CitizenReport(
      reportId: doc.id,
      hazardType: data['hazard_type'] ?? 'General Hazard',
      location: LatLng(geo.latitude, geo.longitude),
      description: data['description'] ?? '',
      photoUrl: data['photo_url'] ?? '',
    );
  }
}

class FusedZone {
  final ESP32NodeData? node;
  final List<CitizenReport> reports;
  final LatLng location;
  final String title;
  final HazardStatus status;
  final int riskScore;
  final List<String> triggers;

  FusedZone({
    this.node,
    required this.reports,
    required this.location,
    required this.title,
    required this.status,
    required this.riskScore,
    required this.triggers,
  });
}

// -----------------------------------------------------------------------------
// Live Dashboard Screen
// -----------------------------------------------------------------------------

class LiveDashboardScreen extends StatefulWidget {
  const LiveDashboardScreen({super.key});

  @override
  State<LiveDashboardScreen> createState() => _LiveDashboardScreenState();
}

class _LiveDashboardScreenState extends State<LiveDashboardScreen> {
  final DatabaseReference _rtdbRef = FirebaseDatabase.instance.ref('telemetry');
  final CollectionReference _firestoreRef =
      FirebaseFirestore.instance.collection('citizen_reports');

  FusedZone? selectedZone;

  List<FusedZone> _processFusion(
      Map<dynamic, dynamic>? rtdbMap, List<DocumentSnapshot> firestoreDocs) {
    List<ESP32NodeData> nodes = [];
    if (rtdbMap != null) {
      rtdbMap.forEach((key, value) {
        if (value is Map) {
          nodes.add(ESP32NodeData.fromMap(key.toString(), value));
        }
      });
    }

    List<CitizenReport> reports =
        firestoreDocs.map((doc) => CitizenReport.fromFirestore(doc)).toList();

    List<FusedZone> fusedZones = [];

    for (var node in nodes) {
      int score = 0;
      List<String> triggers = [];

      if (node.waterLevelCm > 50.0) {
        score += 45;
        triggers.add("FLOOD_LEVEL (${node.waterLevelCm}cm)");
      }
      if (node.accelVibration > 2.0) {
        score += 40;
        triggers.add("HIGH_VIBRATION (${node.accelVibration}g)");
      }
      if (node.pressureHpa < 1000.0 && node.pressureHpa > 0) {
        score += 15;
        triggers.add("LOW_PRESSURE_ANOMALY");
      }

      var nearby = reports.where((r) {
        double dLat = (r.location.latitude - node.location.latitude).abs();
        double dLng = (r.location.longitude - node.location.longitude).abs();
        return dLat < 0.005 && dLng < 0.005;
      }).toList();

      if (nearby.isNotEmpty) {
        score += nearby.length * 20;
        triggers.add("${nearby.length} CROWD_CONFIRMATIONS");
      }

      HazardStatus status;
      if (score >= 65) {
        status = HazardStatus.critical;
      } else if (score >= 30) {
        status = HazardStatus.warning;
      } else {
        status = HazardStatus.normal;
      }

      fusedZones.add(FusedZone(
        node: node,
        reports: nearby,
        location: node.location,
        title: "Node: ${node.nodeId}",
        status: status,
        riskScore: score.clamp(0, 100),
        triggers: triggers,
      ));
    }

    for (var rep in reports) {
      bool alreadyFused = fusedZones.any((z) => z.reports.contains(rep));
      if (!alreadyFused) {
        fusedZones.add(FusedZone(
          node: null,
          reports: [rep],
          location: rep.location,
          title: "Citizen Alert: ${rep.hazardType}",
          status: HazardStatus.citizenOnly,
          riskScore: 35,
          triggers: ["UNVERIFIED_CITIZEN_REPORT"],
        ));
      }
    }

    return fusedZones;
  }

  Color _getStatusColor(HazardStatus status) {
    switch (status) {
      case HazardStatus.critical:
        return Colors.redAccent;
      case HazardStatus.warning:
        return Colors.orangeAccent;
      case HazardStatus.citizenOnly:
        return Colors.amberAccent;
      case HazardStatus.normal:
        return Colors.greenAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JanRakshak Live Monitor'),
        backgroundColor: const Color(0xFF121212),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review_rounded),
            tooltip: "View Crowd Reports Feed",
            onPressed: () => _showAllReportsFeed(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded),
            onPressed: () => _showCitizenReportModal(context),
            tooltip: "Submit Citizen Report",
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _rtdbRef.onValue,
        builder: (context, rtdbSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: _firestoreRef.snapshots(),
            builder: (context, firestoreSnapshot) {
              if (rtdbSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              Map<dynamic, dynamic>? rtdbData;
              if (rtdbSnapshot.hasData && rtdbSnapshot.data!.snapshot.value != null) {
                rtdbData = rtdbSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              }

              List<DocumentSnapshot> docs = firestoreSnapshot.hasData
                  ? firestoreSnapshot.data!.docs
                  : [];

              List<FusedZone> zones = _processFusion(rtdbData, docs);
              selectedZone ??= zones.isNotEmpty ? zones.first : null;

              return Stack(
                children: [
                  FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(12.9340, 79.1360),
                      initialZoom: 13.5,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.janrakshak.app',
                      ),
                      MarkerLayer(
                        markers: zones.map((zone) {
                          final isSelected = selectedZone?.title == zone.title;
                          final color = _getStatusColor(zone.status);

                          return Marker(
                            point: zone.location,
                            width: isSelected ? 55.0 : 42.0,
                            height: isSelected ? 55.0 : 42.0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedZone = zone;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.black45,
                                    width: isSelected ? 3.0 : 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.sensors_rounded,
                                  color: Colors.black,
                                  size: 22,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  if (selectedZone != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 16,
                      child: _buildDetailCard(selectedZone!),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailCard(FusedZone zone) {
    final statusColor = _getStatusColor(zone.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.7), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                zone.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  "Risk Score: ${zone.riskScore}%",
                  style: TextStyle(
                      color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: Colors.white10),
          if (zone.node != null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _badge("Water", "${zone.node!.waterLevelCm} cm", Icons.water_drop),
                _badge("Vib", "${zone.node!.accelVibration} g", Icons.vibration),
                _badge("Temp", "${zone.node!.tempC}°C", Icons.thermostat),
                _badge("Press", "${zone.node!.pressureHpa} hPa", Icons.compress),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (zone.reports.isNotEmpty) ...[
            const Text(
              "Citizen Ground Reports:",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ...zone.reports.map((report) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("• ${report.hazardType}: ${report.description}", style: const TextStyle(fontSize: 12)),
                  if (report.photoUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          report.photoUrl,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text("Image preview error", style: TextStyle(color: Colors.red, fontSize: 10)),
                        ),
                      ),
                    ),
                ],
              ),
            )),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: zone.triggers
                .map((t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.black38,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, String val, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.blueAccent),
        const SizedBox(width: 4),
        Text("$label: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showCitizenReportModal(BuildContext context) {
    final descController = TextEditingController();
    String hazardType = "Flash Flood";
    XFile? pickedFile;
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Submit Citizen Crowd Report",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: hazardType,
                    decoration: const InputDecoration(labelText: "Hazard Type"),
                    items: ["Flash Flood", "Structural Damage", "Road Obstruction"]
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (val) => setModalState(() => hazardType = val!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: "Description",
                      hintText: "Describe conditions (e.g., water depth, damaged wall)",
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: Text(pickedFile == null ? "Attach Photo" : "Change Photo"),
                        onPressed: () async {
                          final ImagePicker picker = ImagePicker();
                          // Downscale and compress image at pick time
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 50,
                            maxWidth: 1024,
                            maxHeight: 1024,
                          );
                          if (image != null) {
                            setModalState(() => pickedFile = image);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      if (pickedFile != null)
                        const Text("Photo Attached ✓", style: TextStyle(color: Colors.greenAccent)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: isUploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(isUploading ? "Uploading..." : "Submit Report"),
                      onPressed: isUploading
                          ? null
                          : () async {
                              setModalState(() => isUploading = true);
                              String? photoUrl;

                              try {
                                if (pickedFile != null) {
                                  final ref = FirebaseStorage.instance
                                      .ref()
                                      .child('report_photos/${DateTime.now().millisecondsSinceEpoch}.jpg');

                                  if (kIsWeb) {
                                    final bytes = await pickedFile!.readAsBytes();
                                    await ref.putData(
                                      bytes,
                                      SettableMetadata(contentType: 'image/jpeg'),
                                    ).timeout(const Duration(seconds: 15));
                                  } else {
                                    await ref.putFile(File(pickedFile!.path)).timeout(const Duration(seconds: 15));
                                  }
                                  photoUrl = await ref.getDownloadURL();
                                }

                                await _firestoreRef.add({
                                  'hazard_type': hazardType,
                                  'description': descController.text,
                                  'photo_url': photoUrl ?? '',
                                  'location': GeoPoint(currentPos.latitude, currentPos.longitude),
                                  'timestamp': FieldValue.serverTimestamp(),
                                });

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Report published successfully!")),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isUploading = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Upload failed/timed out: $e")),
                                  );
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAllReportsFeed(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Live Crowd Hazard Feed",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestoreRef.snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text("No citizen reports submitted yet."),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final report = CitizenReport.fromFirestore(docs[index]);
                            return Card(
                              color: const Color(0xFF2A2A2A),
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Chip(
                                          label: Text(report.hazardType, style: const TextStyle(fontSize: 11)),
                                          backgroundColor: Colors.amber.withValues(alpha: 0.2),
                                          side: const BorderSide(color: Colors.amberAccent),
                                        ),
                                        Text(
                                          "${report.location.latitude.toStringAsFixed(3)}, ${report.location.longitude.toStringAsFixed(3)}",
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      report.description.isEmpty ? "No detailed description." : report.description,
                                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                                    ),
                                    if (report.photoUrl.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          report.photoUrl,
                                          height: 160,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Text("Image preview unavailable", style: TextStyle(color: Colors.red, fontSize: 11)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}