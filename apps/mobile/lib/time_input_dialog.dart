import 'package:flutter/material.dart';

/// Owns input state until the dialog route has finished closing.
class TimeInputDialog extends StatefulWidget {
  const TimeInputDialog({
    super.key,
    required this.title,
    required this.labels,
    required this.values,
    required this.validate,
    this.hint,
    this.action = 'Apply',
  });

  final String title;
  final List<String> labels;
  final List<double> values;
  final String? hint;
  final String action;
  final String? Function(List<double>) validate;

  @override
  State<TimeInputDialog> createState() => _TimeInputDialogState();
}

class _TimeInputDialogState extends State<TimeInputDialog> {
  late final List<TextEditingController> _inputs;
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _inputs = [
      for (final value in widget.values)
        TextEditingController(text: value.toStringAsFixed(3)),
    ];
  }

  void _submit() {
    if (_closing) return;
    final parsed = [
      for (final input in _inputs) double.tryParse(input.text.trim()),
    ];
    if (parsed.any((value) => value == null || !value.isFinite)) {
      setState(() => _error = 'Enter valid numbers');
      return;
    }
    final values = parsed.cast<double>();
    final error = widget.validate(values);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(values);
  }

  @override
  void dispose() {
    for (final input in _inputs) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: AlertDialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Text(widget.title),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.hint != null) Text(widget.hint!),
            for (var i = 0; i < _inputs.length; i++)
              TextField(
                controller: _inputs[i],
                autofocus: false,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                textInputAction: i == _inputs.length - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                onSubmitted: (_) {
                  if (i == _inputs.length - 1) {
                    _submit();
                  } else {
                    FocusScope.of(context).nextFocus();
                  }
                },
                decoration: InputDecoration(labelText: widget.labels[i]),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: _submit, child: Text(widget.action)),
        ],
      ),
    ),
  );
}
