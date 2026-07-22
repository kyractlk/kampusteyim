import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Web'de CORS kırılgan CDN'ler (pravatar vb.) için HTML <img> tercih eder;
/// hata olursa [errorBuilder] / baş harf fallback.
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      filterQuality: FilterQuality.medium,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      errorBuilder: errorBuilder ??
          (context, error, stack) => ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: (width != null && width! < 64) ? 18 : 36,
                    color: Colors.black45,
                  ),
                ),
              ),
    );
  }
}
