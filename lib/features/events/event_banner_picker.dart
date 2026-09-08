import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';

Future<String?> pickEventBanner(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Banner için giriş gerekli')),
    );
    return null;
  }
  final file = await MediaUpload.pickImage();
  if (file == null) return null;
  try {
    return await MediaUpload.uploadXFile(
      file: file,
      folder: 'ads/$uid/events',
      firstName: auth.user?.firstName ?? 'etkinlik',
      lastName: auth.user?.lastName ?? 'banner',
      studentNo: uid,
      isVideo: false,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Banner yüklenemedi: $e')),
      );
    }
    return null;
  }
}

class EventBannerPreview extends StatelessWidget {
  const EventBannerPreview({
    super.key,
    required this.url,
    required this.onPick,
    this.uploading = false,
  });

  final String url;
  final VoidCallback onPick;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kapak / banner',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 7,
          child: Material(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: uploading ? null : onPick,
              child: url.isEmpty
                  ? Center(
                      child: uploading
                          ? const CircularProgressIndicator()
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined),
                                SizedBox(height: 6),
                                Text('Banner seç'),
                              ],
                            ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(url, fit: BoxFit.cover),
                        if (uploading)
                          const ColoredBox(
                            color: Color(0x66000000),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Chip(label: Text('Değiştir')),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
