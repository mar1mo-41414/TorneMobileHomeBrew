/// TV focus support (plan 123): the widgets that make the shared
/// UI operable with a remote control on the TV variant.
///
/// Two recurring problems on TV, both rooted in the D-pad being
/// the only input:
///
///  * A plain [TextField] opens the software keyboard the moment
///    it gains focus, which traps remote navigation: the keyboard
///    swallows the keys, and closing it returns focus to whatever
///    was focused before the field, so traversal cannot move past
///    the field at all (backlog 2026-11-21, Fire TV Stick report).
///    [AppTextField] keeps the standard field on the standard
///    variant and swaps in a focus-only shell on TV: focus shows
///    the value like a field but never opens the keyboard, and
///    pressing OK (or tapping) opens a dedicated edit dialog.
///    Closing the dialog returns focus to the field.
///
///  * A scroll view whose first or last element cannot take focus
///    can never be scrolled to that end with the D-pad, because
///    focus traversal is the only scroll driver on TV (the
///    settings screen's version footer was unreachable this way,
///    plan 121). [TvFocusAnchor] gives a display-only edge item
///    focus — and nothing else — so both ends of a scroll view
///    stay reachable. On the standard variant it is the identity.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/variant.dart';

/// A text field that behaves like a plain [TextField] on the
/// standard variant and like a focus-then-edit shell on TV.
///
/// Only the parameter subset the app actually uses is mirrored;
/// every call site passes its arguments through unchanged, so the
/// standard variant renders the exact same [TextField] as before.
///
/// TV semantics differ from a real field in two deliberate ways:
/// [onChanged] fires once, with the final value, when the edit
/// dialog is confirmed (not per keystroke), and [onSubmitted] is
/// not called — the dialog's confirm button plays that role, and
/// focus returns to the field afterwards instead of leaving it.
class AppTextField extends ConsumerWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.tvEditTitle,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final bool autocorrect;
  final bool enableSuggestions;

  /// Title for the TV edit dialog when the decoration carries no
  /// label of its own (the DTCP paste fields label themselves
  /// outside the field). Falls back to the decoration's label,
  /// then its hint.
  final String? tvEditTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appVariantProvider).isTv) {
      return TextField(
        controller: controller,
        decoration: decoration,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        minLines: minLines,
        maxLines: maxLines,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
      );
    }
    return _TvTextFieldShell(
      controller: controller,
      decoration: decoration,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      tvEditTitle: tvEditTitle,
    );
  }
}

/// The TV presentation of [AppTextField]: an [InputDecorator]
/// box that takes focus and shows the current value, but has no
/// editable text of its own, so the software keyboard never opens
/// during traversal. Activation (remote OK / enter / tap) opens
/// [_TvTextEditDialog].
class _TvTextFieldShell extends StatefulWidget {
  const _TvTextFieldShell({
    required this.controller,
    required this.decoration,
    required this.keyboardType,
    required this.textInputAction,
    required this.onChanged,
    required this.autofocus,
    required this.minLines,
    required this.maxLines,
    required this.autocorrect,
    required this.enableSuggestions,
    required this.tvEditTitle,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final bool autocorrect;
  final bool enableSuggestions;
  final String? tvEditTitle;

  @override
  State<_TvTextFieldShell> createState() => _TvTextFieldShellState();
}

class _TvTextFieldShellState extends State<_TvTextFieldShell> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // The displayed value and the decoration's empty state follow
    // the controller, which the owner (or the edit dialog) writes.
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(_TvTextFieldShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor() async {
    final original = widget.controller.text;
    final title =
        widget.tvEditTitle ??
        widget.decoration.labelText ??
        widget.decoration.hintText;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TvTextEditDialog(
        title: title,
        initialValue: original,
        hintText: widget.decoration.hintText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
      ),
    );
    if (!mounted) return;
    if (result != null && result != original) {
      widget.controller.text = result;
      widget.onChanged?.call(result);
    }
    // The dialog held focus while it was up; put it back on this
    // field so traversal continues from where the user was.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.controller.text;
    final minLines = widget.minLines ?? 1;
    final lineHeight =
        (theme.textTheme.titleMedium?.fontSize ?? 16) *
        (theme.textTheme.titleMedium?.height ?? 1.5);
    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _openEditor();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openEditor,
        child: InputDecorator(
          decoration: widget.decoration,
          isFocused: _focused,
          isEmpty: text.isEmpty,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minLines > 1 ? lineHeight * minLines : 0,
            ),
            child: Text(
              text,
              maxLines: widget.maxLines,
              overflow: (widget.maxLines ?? 1) == 1
                  ? TextOverflow.ellipsis
                  : TextOverflow.clip,
              softWrap: (widget.maxLines ?? 1) != 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The modal editor behind the TV field shell. Editing happens
/// here, where opening the software keyboard is the user's
/// explicit choice rather than a side effect of traversal.
/// Confirming returns the text; cancelling (or dismissing)
/// returns null and leaves the field untouched.
class _TvTextEditDialog extends StatefulWidget {
  const _TvTextEditDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.keyboardType,
    required this.textInputAction,
    required this.minLines,
    required this.maxLines,
    required this.autocorrect,
    required this.enableSuggestions,
  });

  final String? title;
  final String initialValue;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? minLines;
  final int? maxLines;
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  State<_TvTextEditDialog> createState() => _TvTextEditDialogState();
}

class _TvTextEditDialogState extends State<_TvTextEditDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.title == null ? null : Text(widget.title!),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('決定')),
      ],
    );
  }
}

/// Gives a display-only widget focus — and only focus — on the
/// TV variant, so D-pad traversal (and with it, scrolling) can
/// reach it at the edge of a scroll view. The child renders
/// unchanged; a focus ring shows while the anchor holds focus.
/// On the standard variant this is the identity: no focus node,
/// no decoration, no traversal change.
class TvFocusAnchor extends ConsumerStatefulWidget {
  const TvFocusAnchor({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TvFocusAnchor> createState() => _TvFocusAnchorState();
}

class _TvFocusAnchorState extends ConsumerState<TvFocusAnchor> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(appVariantProvider).isTv) return widget.child;
    final theme = Theme.of(context);
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: widget.child,
      ),
    );
  }
}
