import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StepGoalDialog extends StatefulWidget {
  const StepGoalDialog({
    super.key,
    required this.initialGoal,
    required this.onSave,
  });

  final int initialGoal;
  final Future<bool> Function(int value) onSave;

  @override
  State<StepGoalDialog> createState() => _StepGoalDialogState();
}

class _StepGoalDialogState extends State<StepGoalDialog> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.initialGoal}',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = int.tryParse(_text.text);
    if (value == null || value < 1000 || value > 50000) {
      setState(() => _error = '请输入 1,000–50,000 之间的整数');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(value);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('每日步数目标'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('这是个人活动目标，不是医学建议。'),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '每天的目标步数',
              suffixText: '步',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );
}
