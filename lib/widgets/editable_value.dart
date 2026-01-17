import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditableValue extends StatefulWidget {
  final String value;
  final String placeholder;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final bool multiline;
  final ValueChanged<String> onCommit;
  final bool isReadOnly;
  final bool showPlaceholderWhenEmpty;
  final Widget Function(
    BuildContext context,
    String value,
    TextStyle? style,
    TextAlign align,
  )? displayBuilder;

  const EditableValue({
    super.key,
    required this.value,
    required this.onCommit,
    this.placeholder = 'tap to edit',
    this.textStyle,
    this.textAlign = TextAlign.start,
    this.multiline = false,
    this.isReadOnly = false,
    this.showPlaceholderWhenEmpty = true,
    this.displayBuilder,
  });

  @override
  State<EditableValue> createState() => _EditableValueState();
}

class _EditableValueState extends State<EditableValue> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;
  String _startValue = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant EditableValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _startValue = widget.value;
      _controller.text = widget.value;
    });
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _commit() {
    final newValue = _controller.text;
    setState(() {
      _editing = false;
    });
    if (newValue != _startValue) {
      widget.onCommit(newValue);
    }
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _controller.text = _startValue;
    });
  }

  bool _isCtrlOrMetaPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.textStyle ?? Theme.of(context).textTheme.bodyMedium;
    if (_editing) {
      return Focus(
        focusNode: _focusNode,
        onFocusChange: (hasFocus) {
          if (!hasFocus) {
            _commit();
          }
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _cancel();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (!widget.multiline || _isCtrlOrMetaPressed()) {
                _commit();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: widget.multiline ? 6 : 1,
          minLines: widget.multiline ? 1 : 1,
          textAlign: widget.textAlign,
          style: textStyle,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          ),
          onSubmitted: widget.multiline ? null : (_) => _commit(),
        ),
      );
    }

    final isEmpty = widget.value.trim().isEmpty;
    final showPlaceholder = widget.showPlaceholderWhenEmpty && isEmpty;
    final displayText = showPlaceholder ? widget.placeholder : widget.value;
    final displayStyle = showPlaceholder
        ? textStyle?.copyWith(
            color: Theme.of(context).hintColor,
            fontStyle: FontStyle.italic,
          )
        : textStyle;

    final displayChild =
        showPlaceholder || isEmpty || widget.displayBuilder == null
            ? Text(
                displayText,
                style: displayStyle,
                textAlign: widget.textAlign,
              )
            : widget.displayBuilder!(
                context,
                widget.value,
                displayStyle,
                widget.textAlign,
              );

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: displayChild,
    );

    if (widget.isReadOnly) {
      return content;
    }

    return InkWell(
      onTap: _startEdit,
      child: content,
    );
  }
}
