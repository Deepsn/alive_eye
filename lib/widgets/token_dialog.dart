import 'package:flutter/material.dart';

import '../config/app_config.dart';

Future<String?> showTokenDialog(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TokenDialog(current: current),
  );
}

class _TokenDialog extends StatefulWidget {
  const _TokenDialog({this.current});

  final String? current;

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('SPTrans API token'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          const Text('Create a free Olho Vivo token at'),
          const SelectableText(AppConfig.developerPortalUrl),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Token',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
