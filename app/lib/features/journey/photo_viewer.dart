import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../widgets/common.dart';

/// Full-screen photos with pinch-zoom and the photographer's credit.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, this.initial = 0});

  final List<Photo> photos;
  final int initial;

  static Future<void> open(BuildContext context, List<Photo> photos, int initial) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => PhotoViewer(photos: photos, initial: initial),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final credit = photo.credit;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: TgImage(widget.photos[i].url, fit: BoxFit.contain, semanticLabel: widget.photos[i].caption),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    const Spacer(),
                    Text('${_index + 1} / ${widget.photos.length}', style: TT.ui(12, color: Colors.white70)),
                    const SizedBox(width: 16),
                  ],
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  color: Colors.black54,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(photo.caption, style: TT.display(20, color: Colors.white)),
                      if (credit != null && credit.author.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: credit.source == null
                              ? null
                              : () => launchUrl(Uri.parse(credit.source!), mode: LaunchMode.externalApplication),
                          child: Text(
                            'Photo: ${credit.author} · ${credit.license}${credit.source != null ? ' · source ↗' : ''}',
                            style: TT.ui(12.5, color: Colors.white70),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
