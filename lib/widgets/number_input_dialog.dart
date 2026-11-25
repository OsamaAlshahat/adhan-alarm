import 'package:flutter/material.dart';
import '../core/localization/tr.dart';

Future<int?> showNumberInputDialog(
  BuildContext context, {
  required String title,
  required int current,
  required int max,
  int min = 0,
}) async {
  final controller = TextEditingController(text: '$current');
  return showDialog<int>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: '$min - $max'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx),
          child: Text(Tr.t(dCtx, 'Cancel', 'إلغاء')),
        ),
        FilledButton(
          onPressed: () {
            final val = int.tryParse(controller.text);
            if (val != null && val >= min && val <= max) {
              Navigator.pop(dCtx, val);
            }
          },
          child: Text(Tr.t(dCtx, 'OK', 'موافق')),
        ),
      ],
    ),
  );
}

