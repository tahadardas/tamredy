import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

/// Nurse vital observations & clinical notes screen.
/// Uses exact observationType codes constrained in migration 045:
/// SYSTOLIC_BP, DIASTOLIC_BP, HEART_RATE, TEMPERATURE, O2_SATURATION, BLOOD_GLUCOSE, PAIN_SCORE.
class NurseClinicalNotesScreen extends StatefulWidget {
  final NurseSessionCoordinator session;
  final String requestId;
  final String patientName;

  const NurseClinicalNotesScreen({
    super.key,
    required this.session,
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
      final obsList = <Map<String, dynamic>>[];
      if (data.systolic != null) {
        obsList.add({
          'observationType': 'SYSTOLIC_BP',
          'numericValue': data.systolic,
          'unit': 'mmHg',
        });
      }
      if (data.diastolic != null) {
        obsList.add({
          'observationType': 'DIASTOLIC_BP',
          'numericValue': data.diastolic,
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
          'observationType': 'O2_SATURATION',
          'numericValue': data.oxygenSaturation,
          'unit': '%',
        });
      }
      if (data.temperature != null) {
        obsList.add({
          'observationType': 'TEMPERATURE',
          'numericValue': data.temperature,
          'unit': '°C',
        });
      }
      obsList.add({
        'observationType': 'PAIN_SCORE',
        'numericValue': data.painLevel,
        'unit': '0-10',
      });

      if (!kDemoMode) {
        if (obsList.isNotEmpty) {
          await widget.session.api.post('/v1/health-records/observations', {
            'requestId': widget.requestId,
            'observations': obsList,
          });
        }
        if (data.notes.trim().isNotEmpty) {
          await widget.session.api.post('/v1/health-records/notes', {
            'requestId': widget.requestId,
            'clinicalNotes': data.notes.trim(),
          });
        }
      }

      if (mounted) {
        TamToast.show(context, 'تم توثيق العلامات الحيوية والملاحظات بنجاح', tone: TamToastTone.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        TamToast.show(
          context,
          explainError(e, fallback: 'تعذر حفظ العلامات الحيوية. حاول مجدداً.'),
          tone: TamToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: tc.background,
        appBar: AppBar(
          backgroundColor: tc.surface,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'التوثيق السريري — ${widget.patientName}',
            style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
          ),
        ),
        body: _isSaving
            ? const Center(child: CircularProgressIndicator())
            : AeroObservationsSheet(
                onSave: _handleSaveObservations,
              ),
      ),
    );
  }
}
