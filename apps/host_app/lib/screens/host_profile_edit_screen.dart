import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/host_profile_service.dart';

class HostProfileEditScreen extends StatefulWidget {
  const HostProfileEditScreen({super.key, required this.profile, required this.service});
  final Map<String, dynamic> profile;
  final HostProfileService service;
  @override
  State<HostProfileEditScreen> createState() => _HostProfileEditScreenState();
}

class _HostProfileEditScreenState extends State<HostProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _bio;
  final _picker = ImagePicker();
  String? _avatarUrl;
  Uint8List? _bytes;
  String? _extension;
  String? _mime;
  bool _saving = false;
  bool _uploading = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: (widget.profile['display_name'] as String?) ?? '')..addListener(_markDirty);
    _bio = TextEditingController(text: (widget.profile['bio'] as String?) ?? '')..addListener(_markDirty);
    _avatarUrl = widget.profile['avatar_url'] as String?;
  }
  void _markDirty() { if (mounted && !_saving) setState(() => _dirty = true); }
  String _friendly(Object e) => e.toString().replaceFirst(RegExp(r'^(Exception|Bad state|Invalid argument): '), '');

  Future<void> _chooseAvatar() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600, maxHeight: 1600);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final filename = file.name.toLowerCase();
      final ext = filename.contains('.') ? filename.split('.').last : '';
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp', _ => '',
      };
      if (mime.isEmpty) { _message('Choose a JPG, PNG or WebP image.'); return; }
      if (bytes.length > 5 * 1024 * 1024) { _message('Choose an image smaller than 5 MB.'); return; }
      setState(() { _bytes = bytes; _extension = ext; _mime = mime; _dirty = true; });
    } catch (e) { if (mounted) _message(_friendly(e)); }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.service.saveProfile(displayName: _name.text, bio: _bio.text);
      if (_bytes != null) {
        setState(() => _uploading = true);
        _avatarUrl = await widget.service.uploadAvatar(bytes: _bytes!, extension: _extension!, contentType: _mime!);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => _error = _friendly(e)); }
    finally { if (mounted) setState(() { _saving = false; _uploading = false; }); }
  }
  void _message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating));

  @override
  void dispose() { _name.removeListener(_markDirty); _bio.removeListener(_markDirty); _name.dispose(); _bio.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final username = (widget.profile['username'] as String?)?.trim();
    final ImageProvider? image = _bytes != null ? MemoryImage(_bytes!) :
      (_avatarUrl != null && _avatarUrl!.isNotEmpty ? NetworkImage(_avatarUrl!) : null);
    return Scaffold(appBar: AppBar(title: const Text('Edit profile')), body: SafeArea(child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: Form(key: _formKey,
        child: ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 32), children: [
          Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFF141821), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF2B3240))),
            child: Column(children: [
              Stack(alignment: Alignment.bottomRight, children: [
                CircleAvatar(radius: 50, backgroundColor: const Color(0xFF29243D), backgroundImage: image, child: image == null ? const Icon(Icons.person, size: 46) : null),
                Material(color: const Color(0xFF9B8AFB), shape: const CircleBorder(), child: IconButton(tooltip: 'Choose profile photo', onPressed: _saving ? null : _chooseAvatar, icon: const Icon(Icons.camera_alt, color: Color(0xFF100D20)))),
              ]),
              TextButton.icon(onPressed: _saving ? null : _chooseAvatar, icon: const Icon(Icons.photo_library_outlined), label: const Text('Change photo')),
              const Text('JPG, PNG or WebP · up to 5 MB', style: TextStyle(color: Color(0xFF9299A8), fontSize: 11)),
            ])),
          const SizedBox(height: 18),
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF141821), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF2B3240))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(controller: _name, maxLength: 60, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Display name', hintText: 'How people see you', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a display name.' : ((v ?? '').trim().length > 60 ? 'Use 60 characters or fewer.' : null)),
              const SizedBox(height: 8),
              InputDecorator(decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email_rounded), helperText: 'Your username is managed by your account.'),
                child: Text(username == null || username.isEmpty ? 'Username not set' : '@$username')),
              const SizedBox(height: 16),
              TextFormField(controller: _bio, maxLength: 500, maxLines: 5, minLines: 3, textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Bio', hintText: 'Tell people a little about yourself', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes_rounded))),
              if (_error != null) ...[
                const SizedBox(height: 12), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF351C26), borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFFC0CB)))),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: _saving || !_dirty ? null : _save,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF100D20))) : const Icon(Icons.save_outlined),
                label: Text(_uploading ? 'Uploading photo…' : (_saving ? 'Saving…' : 'Save changes'))),
            ])),
        ])),
      ),
    )));
  }
}
