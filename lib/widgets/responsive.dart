import 'package:flutter/material.dart';

class ResponsiveBreakpoints {
  static const double tablet = 720;
  static const double desktop = 1024;
  static const double maxContentWidth = 1200;
}

bool isTablet(BuildContext context) {
  return MediaQuery.of(context).size.width >= ResponsiveBreakpoints.tablet;
}

bool isDesktop(BuildContext context) {
  return MediaQuery.of(context).size.width >= ResponsiveBreakpoints.desktop;
}

double horizontalPaddingForWidth(double width) {
  if (width >= 1400) return 80;
  if (width >= 1100) return 56;
  if (width >= 900) return 40;
  if (width >= 720) return 28;
  return 20;
}

EdgeInsets pagePadding(BuildContext context) {
  return EdgeInsets.symmetric(
    horizontal: horizontalPaddingForWidth(MediaQuery.of(context).size.width),
  );
}

class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  final Alignment alignment;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = ResponsiveBreakpoints.maxContentWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final resolvedPadding = padding ??
            EdgeInsets.symmetric(horizontal: horizontalPaddingForWidth(width));
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: resolvedPadding,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
