import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChildProfileScreen extends StatefulWidget {
  static const routeName = '/child-profile';
  const ChildProfileScreen({super.key});

  @override
  State<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen> {
  final _nameCtrl = TextEditingController();
  DateTime? _dob;
  String? _gender;
  int _age = 0;
  int _difficulty = 1;
  final _api = ApiService();
  bool _loading = false;
  String? _error;

  void _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 8),
      firstDate: DateTime(now.year - 18),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        final years = now.year - picked.year - ((now.month < picked.month || (now.month == picked.month && now.day < picked.day)) ? 1 : 0);
        _age = years;
      });
    }
  }

  Future<void> _saveAndContinue(String parentEmail) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty || _age <= 0 || _dob == null || _gender == null) {
        throw Exception('Enter name, DOB, gender; age is auto-calculated');
      }
      final dobStr = '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';
      await _api.createChild(
        parentEmail: parentEmail,
        name: name,
        age: _age,
        difficulty: _difficulty,
        dob: dobStr,
        gender: _gender!,
      );
      if (!mounted) return;
      // After child profile creation, go to dashboard to see the child.
      Navigator.pushReplacementNamed(context, '/dashboard', arguments: parentEmail);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentEmail = ModalRoute.of(context)!.settings.arguments as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Child Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Child name'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(_dob == null ? 'DOB: not set' : 'DOB: ${_dob!.day}/${_dob!.month}/${_dob!.year}'),
                ),
                TextButton(
                  onPressed: _pickDob,
                  child: const Text('Select DOB'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Age (years): ${_age > 0 ? _age : '-'}'),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              value: _gender,
              hint: const Text('Select gender'),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 8),
            const Text(
              'How much learning difficulty do you observe for this child?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            DropdownButton<int>(
              isExpanded: true,
              value: _difficulty,
              items: const [
                DropdownMenuItem(
                  value: 1,
                  child: Text('Mild – small occasional problems'),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('Moderate – regular learning difficulties'),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text('Severe – major ongoing difficulties'),
                ),
              ],
              onChanged: (v) => setState(() => _difficulty = v ?? 1),
            ),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _saveAndContinue(parentEmail),
                  child: const Text('Save Profile'),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }
}

