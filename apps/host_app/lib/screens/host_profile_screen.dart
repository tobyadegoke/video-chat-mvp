import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/host_profile_service.dart';

class HostProfileScreen extends StatefulWidget {
  const HostProfileScreen({super.key, this.service});

  final HostProfileService? service;

  @override
  State<HostProfileScreen> createState() => _HostProfileScreenState();
}

class _HostProfileScreenState extends State<HostProfileScreen> {
  late final HostProfileService _service =
      widget.service ?? HostProfileService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _picker = ImagePicker();

  String? _username;
  String? _avatarUrl;
  Uint8List? _pendingAvatarBytes;
  String? _pendingExtension;
  String? _pendingContentType;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _error;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
    _nameController.addListener(_markDirty);
    _bioController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_loading && mounted) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _service.loadProfile();
      if (!mounted) return;
      _nameController.text = (profile['display_name'] as String?) ?? '';
      _bioController.text = (profile['bio'] as String?) ?? '';
      setState(() {
        _username = profile['username'] as String?;
        _avatarUrl = profile['avatar_url'] as String?;
        _pendingAvatarBytes = null;
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|Bad state|Invalid argument): '), '');

  Future<void> _chooseAvatar() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : '';
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => '',
      };
      if (mime.isEmpty) {
        _showMessage('Choose a JPG, PNG or WebP image.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _showMessage('Choose an image smaller than 5 MB.');
        return;
      }
      setState(() {
        _pendingAvatarBytes = bytes;
        _pendingExtension = ext;
        _pendingContentType = mime;
        _dirty = true;
      });
    } catch (e) {
      if (mounted) _showMessage(_friendlyError(e));
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveProfile(
        displayName: _nameController.text,
        bio: _bioController.text,
      );
      if (_pendingAvatarBytes != null) {
        setState(() => _uploadingAvatar = true);
        final url = await _service.uploadAvatar(
          bytes: _pendingAvatarBytes!,
          extension: _pendingExtension!,
          contentType: _pendingContentType!,
        );
        _avatarUrl = url;
      }
      if (!mounted) return;
      setState(() {
        _pendingAvatarBytes = null;
        _pendingExtension = null;
        _pendingContentType = null;
        _dirty = false;
      });
      _showMessage('Profile saved.');
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingAvatar = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _nameController.removeListener(_markDirty);
    _bioController.removeListener(_markDirty);
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _username == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off_outlined, size: 42),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
            children: [
              Text(
                'Creator profile',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Make it easy for people to recognize you.',
                style: TextStyle(color: Color(0xFF9299A8)),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF141821),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF2B3240)),
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFF29243D),
                          backgroundImage: _pendingAvatarBytes != null
                              ? MemoryImage(_pendingAvatarBytes!)
                              : (_avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? NetworkImage(_avatarUrl!)
                                  : null) as ImageProvider?,
                          child: (_pendingAvatarBytes == null &&
                                  (_avatarUrl == null || _avatarUrl!.isEmpty))
                              ? const Icon(Icons.person, size: 48)
                              : null,
                        ),
                        Material(
                          color: const Color(0xFF9B8AFB),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Choose profile photo',
                            onPressed: _saving ? null : _chooseAvatar,
                            icon: const Icon(Icons.camera_alt,
                                color: Color(0xFF100D20)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (_nameController.text.trim().isEmpty)
                          ? 'Your creator profile'
                          : _nameController.text.trim(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_username != null && _username!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('@$_username',
                          style: const TextStyle(
                              color: Color(0xFF9299A8), fontSize: 13)),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _saving ? null : _chooseAvatar,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Change photo'),
                    ),
                    const Text(
                      'JPG, PNG or WebP · up to 5 MB',
                      style: TextStyle(
                          color: Color(0xFF9299A8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF141821),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF2B3240)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Profile details',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _nameController,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          hintText: 'How people see you',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Enter a display name.';
                          }
                          if (value!.trim().length > 60) {
                            return 'Use 60 characters or fewer.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _bioController,
                        maxLength: 500,
                        maxLines: 5,
                        minLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          hintText: 'Tell people a little about yourself',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Your username is managed by your account and cannot be changed here.',
                        style: TextStyle(
                            color: Color(0xFF9299A8), fontSize: 12),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF351C26),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFFFC0CB)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving || (!_dirty)
                            ? null
                            : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF100D20)),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_uploadingAvatar
                            ? 'Uploading photo…'
                            : _saving
                                ? 'Saving…'
                                : 'Save profile'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
