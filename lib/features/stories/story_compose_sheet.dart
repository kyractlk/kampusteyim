import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import 'stories_provider.dart';

Future<void> showStoryComposeSheet(BuildContext context) async {
  if (!AuthGate.requireAuth(
    context,
    message: 'Hikâye paylaşmak için giriş yapmalısın.',
  )) {
    return;
  }
  final auth = context.read<AuthProvider>();
  final user = auth.user;
  if (user == null) return;
  if (user.isSpectatorMode) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('İzleyici modunda hikâye paylaşamazsın.'),
      ),
    );
    return;
  }
  if (!user.canUseStories) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hikâye paylaşımı şu an kullanılamıyor.')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => const _StoryComposeBody(),
  );
}

class _StoryComposeBody extends StatefulWidget {
  const _StoryComposeBody();

  @override
  State<_StoryComposeBody> createState() => _StoryComposeBodyState();
}

class _StoryComposeBodyState extends State<_StoryComposeBody> {
  XFile? _file;
  bool _busy = false;

  Future<void> _pick() async {
    try {
      final file = await MediaUpload.pickImage();
      if (!mounted) return;
      setState(() => _file = file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Görsel seçilemedi: $e')),
      );
    }
  }

  Future<void> _post() async {
    final file = _file;
    final user = context.read<AuthProvider>().user;
    if (file == null || user == null) return;
    setState(() => _busy = true);
    final err = await context.read<StoriesProvider>().createStory(
          author: user,
          file: file,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hikâye paylaşıldı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Hikâye paylaş',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            '24 saat sonra otomatik silinir.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_file == null ? 'Görsel seç' : 'Görsel değiştir'),
          ),
          if (_file != null) ...[
            const SizedBox(height: 10),
            Text(
              _file!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_busy || _file == null) ? null : _post,
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Paylaş'),
          ),
        ],
      ),
    );
  }
}
