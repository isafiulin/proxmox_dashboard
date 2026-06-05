import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:frontend/core/design/app_colors.dart';

class ScrollablePageFrame extends StatefulWidget {
  const ScrollablePageFrame({
    required this.child,
    required this.padding,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<ScrollablePageFrame> createState() => _ScrollablePageFrameState();
}

class _ScrollablePageFrameState extends State<ScrollablePageFrame> {
  static const double _showButtonAfterOffset = 320;
  static const double _floatingButtonInset = 24;

  final ScrollController _controller = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'ScrollablePageFrame');

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToTop() => _animateTo(0);

  void _scrollToBottom() {
    if (!_controller.hasClients) {
      return;
    }
    _animateTo(_controller.position.maxScrollExtent);
  }

  void _animateTo(double offset) {
    if (!_controller.hasClients) {
      return;
    }
    _controller.animateTo(
      offset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.home): _scrollToTop,
        const SingleActivator(LogicalKeyboardKey.end): _scrollToBottom,
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
              controller: _controller,
              padding: widget.padding.add(
                const EdgeInsets.only(bottom: _floatingButtonInset * 3),
              ),
              child: widget.child,
            ),
            Positioned(
              right: _floatingButtonInset,
              bottom: _floatingButtonInset,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  final visible =
                      _controller.hasClients &&
                      _controller.offset > _showButtonAfterOffset;

                  return AnimatedScale(
                    scale: visible ? 1 : 0.82,
                    duration: const Duration(milliseconds: 160),
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: IgnorePointer(ignoring: !visible, child: child),
                    ),
                  );
                },
                child: FloatingActionButton.small(
                  heroTag: 'scroll-to-top',
                  tooltip: 'Наверх',
                  backgroundColor: AppColors.surface,
                  foregroundColor: theme.colorScheme.primary,
                  elevation: 3,
                  onPressed: _scrollToTop,
                  child: const Icon(Icons.keyboard_arrow_up),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
