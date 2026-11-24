import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_typography.dart';
import 'aero_button.dart';

class AeroObservationsData {
  final int? systolic;
  final int? diastolic;
  final int? heartRate;
  final double? bloodGlucose;
  final int? oxygenSaturation;
  final double? temperature;
  final int painLevel;
  final String notes;

  const AeroObservationsData({
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.bloodGlucose,
    this.oxygenSaturation,
    this.temperature,
    this.painLevel = 0,
    this.notes = '',
  });
}

class AeroObservationsSheet extends StatefulWidget {
  final ValueChanged<AeroObservationsData> onSave;
  final AeroObservationsData? initialData;

  const AeroObservationsSheet({
    super.key,
    required this.onSave,
    this.initialData,
  });

  @override
  State<AeroObservationsSheet> createState() => _AeroObservationsSheetState();
}

class _AeroObservationsSheetState extends State<AeroObservationsSheet> {
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _heartRateController = TextEditingController();
  final _glucoseController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _tempController = TextEditingController();
  final _notesController = TextEditingController();
  double _painLevel = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      if (d.systolic != null) _systolicController.text = d.systolic.toString();
      if (d.diastolic != null) _diastolicController.text = d.diastolic.toString();
      if (d.heartRate != null) _heartRateController.text = d.heartRate.toString();
      if (d.bloodGlucose != null) _glucoseController.text = d.bloodGlucose.toString();
      if (d.oxygenSaturation != null) _spo2Controller.text = d.oxygenSaturation.toString();
      if (d.temperature != null) _tempController.text = d.temperature.toString();
      if (d.notes.isNotEmpty) _notesController.text = d.notes;
      _painLevel = d.painLevel.toDouble();
    }
  }

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _heartRateController.dispose();
    _glucoseController.dispose();
    _spo2Controller.dispose();
    _tempController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final data = AeroObservationsData(
      systolic: int.tryParse(_systolicController.text),
      diastolic: int.tryParse(_diastolicController.text),
      heartRate: int.tryParse(_heartRateController.text),
      bloodGlucose: double.tryParse(_glucoseController.text),
      oxygenSaturation: int.tryParse(_spo2Controller.text),
      temperature: double.tryParse(_tempController.text),
      painLevel: _painLevel.round(),
      notes: _notesController.text.trim(),
    );

    Navigator.of(context).pop();
    widget.onSave(data);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.monitor_heart, color: AeroColors.accentTeal),
                const SizedBox(width: 8),
                Text(
                  'توثيق العلامات الحيوية والملاحظات السريرية',
                  style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Blood Pressure
            Row(
              children: [
                Expanded(
                  child: _buildMetricField(
                    label: 'الضغط الانقباضي',
                    unit: 'mmHg',
                    controller: _systolicController,
                    hint: '120',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricField(
                    label: 'الضغط الانبساطي',
                    unit: 'mmHg',
                    controller: _diastolicController,
                    hint: '80',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Heart Rate & SpO2
            Row(
              children: [
                Expanded(
                  child: _buildMetricField(
                    label: 'النبض',
                    unit: 'bpm',
                    controller: _heartRateController,
                    hint: '75',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricField(
                    label: 'تشبع الأكسجين',
                    unit: '%',
                    controller: _spo2Controller,
                    hint: '98',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Glucose & Temperature
            Row(
              children: [
                Expanded(
                  child: _buildMetricField(
                    label: 'سكر الدم',
                    unit: 'mg/dL',
                    controller: _glucoseController,
                    hint: '110',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricField(
                    label: 'الحرارة',
                    unit: '°C',
                    controller: _tempController,
                    hint: '37.0',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Pain Level Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('مستوى الألم (VAS):', style: aeroText(size: 14, weight: FontWeight.w600)),
                Text('${_painLevel.round()} / 10', style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.accentTeal)),
              ],
            ),
            Slider(
              value: _painLevel,
              min: 0,
              max: 10,
              divisions: 10,
              activeColor: AeroColors.accentTeal,
              label: '${_painLevel.round()}',
              onChanged: (v) => setState(() => _painLevel = v),
            ),
            const SizedBox(height: 12),

            // Clinical Notes Field
            Text('الملاحظات السريرية والتوصيات:', style: aeroText(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              style: aeroText(size: 13),
              decoration: InputDecoration(
                hintText: 'اكتب الملاحظات والتوصيات الموجهة للمريض...',
                hintStyle: aeroText(size: 13, color: AeroColors.textMuted),
                filled: true,
                fillColor: AeroColors.lightCanvas,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AeroColors.borderSubtle),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Save CTA
            AeroButton.teal(
              'حفظ وتوثيق في سجل الزيارة',
              onPressed: _handleSave,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricField({
    required String label,
    required String unit,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ($unit)', style: aeroText(size: 12, weight: FontWeight.w600, color: AeroColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: aeroText(size: 14, color: AeroColors.textMuted),
            filled: true,
            fillColor: AeroColors.lightCanvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AeroColors.borderSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
