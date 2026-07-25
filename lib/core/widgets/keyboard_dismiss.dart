import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Odak dışına dokununca klavyeyi kapatır; TextField / buton / scroll bozulmaz.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _dismissIfOutsideFocused,
      child: child,
    );
  }

  static void _dismissIfOutsideFocused(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;

    final focusContext = focus.context;
    if (focusContext == null) {
      focus.unfocus();
      return;
    }

    final box = focusContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      focus.unfocus();
      return;
    }

    final target = _editableRenderBox(focusContext) ?? box;
    final topLeft = target.localToGlobal(Offset.zero);
    final padded = (topLeft & target.size).inflate(8);
    if (!padded.contains(event.position)) {
      focus.unfocus();
    }
  }

  static RenderBox? _editableRenderBox(BuildContext focusContext) {
    RenderBox? found;

    void visitElement(Element el) {
      if (found != null) return;
      if (el.widget is EditableText) {
        final ro = el.renderObject;
        if (ro is RenderBox) found = ro;
        return;
      }
      el.visitChildren(visitElement);
    }

    focusContext.visitChildElements(visitElement);
    if (found != null) return found;

    void visitRo(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visitRo);
    }

    final root = focusContext.findRenderObject();
    if (root != null) visitRo(root);
    return found;
  }
}
