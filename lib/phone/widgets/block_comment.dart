import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/block.dart';
import 'neo.dart';

/// Edit the single comment carried by a block's change — from the "Now" hero
/// (the live block) or from a past block on the timeline. Saving an empty note
/// clears it.
Future<void> editBlockComment(BuildContext context, WidgetRef ref, Block block) async {
  final controller = TextEditingController(text: block.comment ?? '');
  final t = neo(context);
  final result = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.line, width: 3),
        borderRadius: BorderRadius.zero,
      ),
      title: Text('NOTE', style: mono(context, weight: FontWeight.w800)),
      // An explicit width, not the field's intrinsic one. AlertDialog sizes its
      // content to what the child asks for, and an unconstrained TextField asks
      // for however wide its text is — so the dialog grew keystroke by keystroke
      // instead of wrapping, and only stopped once it hit the screen. Same fix,
      // same reason as the CSV preview in reports_screen.dart.
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: mono(context, weight: FontWeight.w700),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: mono(context)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(
            'SAVE',
            style: mono(context, weight: FontWeight.w800, color: t.brand),
          ),
        ),
      ],
    ),
  );
  if (result == null) return; // dismissed
  final text = result.trim();
  await ref
      .read(changeRepositoryProvider)
      .setComment(block.change.syncId, text.isEmpty ? null : text);
}
