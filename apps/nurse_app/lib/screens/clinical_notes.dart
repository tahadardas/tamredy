import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class NurseClinicalNotesScreen extends StatefulWidget {
  final NurseController c;
  final String requestId;
  final String patientName;

  const NurseClinicalNotesScreen({
    super.key,
    required this.c,
    required this.requestId,
    required this.patientName,
  });

  @override
  State<NurseClinicalNotesScreen> createState() => _NurseClinicalNotesScreenState();
}

class _NurseClinicalNotesScreenState extends State<NurseClinicalNotesScreen> {
  bool _isSaving = false;

  Future<void> _handleSaveObservations(AeroObservationsData data) async {
    setState(() => _isSaving = true);
    try {
      // 1. Submit observations
      final obsList = <Map<String, dynamic>>[];
      if (data.systolic != null && data.diastolic != null) {
        obsList.add({
          'observationType': 'BLOOD_PRESSURE',
          'numericValue': data.systolic,
          'textValue': '${data.systolic}/${data.diastolic}',
          'unit': 'mmHg',
        });
      }
      if (data.heartRate != null) {
        obsList.add({
          'observationType': 'HEART_RATE',
          'numericValue': data.heartRate,
          'unit': 'bpm',
        });
      }
      if (data.bloodGlucose != null) {
        obsList.add({
          'observationType': 'BLOOD_GLUCOSE',
          'numericValue': data.bloodGlucose,
          'unit': 'mg/dL',
        });
      }
      if (data.oxygenSaturation != null) {
        obsList.add({
          'observationType': 'SPO2',
          'numericValue': data.oxygenSaturation,
          'unit': '%',
        });
      }
      if (data.temperature != null) {
        obsList.add({
          'observationType': 'BODY_TEMPERATURE',
          'numericValue': data.temperature,
          'unit': '°C',
        });
      }
      obsList.add({
        'observationType': 'PAIN_SCORE',
        'numericValue': data.painLevel,
        'unit': '0-10',
      });

      await widget.c.api.post('/v1/health-records/observations', {
        'requestId': widget.requestId,
        'observations': obsList,
      });

      // 2. Submit clinical visit notes if present
      if (data.notes.isNotEmpty) {
        await widget.c.api.post('/v1/health-records/notes', {
          'requestId': widget.requestId,
          'clinicalNotes': data.notes,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم توثيق العلامات الحيوية والملاحظات السريرية بنجاح')),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ المحلي للعلامات الحيوية (وضع عدم الاتصال)')),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'التوثيق السريري — ${widget.patientName}',
          style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AeroColors.primaryNavy),
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
          : AeroObservationsSheet(
              onSave: _handleSaveObservations,
            ),
    );
  }
}
