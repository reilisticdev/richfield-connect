// mobile/lib/screens/edit_profile_screen.dart
//
// The screen behind Portfolio's "Edit Details" button.
//
// Why nothing happened before: SecondaryButton declares
// `final VoidCallback? onPressed;` as an OPTIONAL parameter, and the
// Portfolio screen built it as
//
//     SecondaryButton(label: 'Edit Details', icon: Icons.edit_outlined)
//
// with no onPressed at all. Flutter's OutlinedButton treats a null
// onPressed as "disabled", so the widget rendered greyed out and swallowed
// every tap. It wasn't a broken handler — there was no handler, and the
// button was disabled at the framework level.
//
// The avatar had the same shape of problem: the little camera badge was a
// decorative Container inside a Stack with no GestureDetector anywhere.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart' show AppColors, AppRadius, AppSpace, AppText;
import '../services/auth_error_mapper.dart';
import '../services/media_service.dart';
import '../services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.userId,
    required this.profile,
    required this.profileService,
    required this.mediaService,
  });

  final String userId;
  final Map<String, dynamic> profile;
  final ProfileService profileService;
  final MediaService mediaService;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _headline;
  late final TextEditingController _interests;
  late final TextEditingController _bio;
  late final TextEditingController _github;
  late final TextEditingController _linkedin;
  late final TextEditingController _website;

  /// Locally chosen but not yet uploaded. Held here so the user sees the
  /// new picture immediately and only pays the upload cost on Save.
  PickedMedia? _pendingAvatar;
  late String? _avatarPath = widget.profile['avatar_path'] as String?;

  bool _saving = false;
  String? _error;

  String _s(String key) => (widget.profile[key] as String?) ?? '';

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(text: _s('first_name'));
    _lastName = TextEditingController(text: _s('last_name'));
    _headline = TextEditingController(text: _s('professional_headline'));
    _interests = TextEditingController(text: _s('career_interests'));
    _bio = TextEditingController(text: _s('bio'));
    _github = TextEditingController(text: _s('github_url'));
    _linkedin = TextEditingController(text: _s('linkedin_url'));
    _website = TextEditingController(text: _s('website_url'));
  }

  @override
  void dispose() {
    for (final c in [
      _firstName, _lastName, _headline, _interests, _bio, _github, _linkedin, _website,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await widget.mediaService.pickImage(source: ImageSource.gallery);
      // null means the user backed out of the picker. Normal, not an error.
      if (picked == null || !mounted) return;
      setState(() {
        _pendingAvatar = picked;
        _error = null;
      });
    } on MediaException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthErrorMapper.fromAny(e));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Upload first: if storage fails we must not write a row pointing at
      // an object that doesn't exist.
      var avatarPath = _avatarPath;
      if (_pendingAvatar != null) {
        avatarPath = await widget.mediaService.uploadAvatar(
          userId: widget.userId,
          media: _pendingAvatar!,
        );
      }

      final updated = await widget.profileService.updateOwnProfile(
        userId: widget.userId,
        firstName: _firstName.text,
        lastName: _lastName.text,
        professionalHeadline: _headline.text,
        careerInterests: _interests.text,
        bio: _bio.text,
        githubUrl: _github.text,
        linkedinUrl: _linkedin.text,
        websiteUrl: _website.text,
        avatarPath: avatarPath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile updated'), duration: Duration(seconds: 2)),
      );
      // Hand the fresh row back so Portfolio repaints from the database's
      // version of the truth, not from what we hoped we wrote.
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AuthErrorMapper.fromAny(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Edit profile', style: AppText.headlineSm()),
        backgroundColor: AppColors.surface,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text('Save', style: AppText.labelLg(color: AppColors.primary)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(AppSpace.base),
          children: [
            Center(child: _avatarPicker()),
            SizedBox(height: AppSpace.lg),

            _sectionLabel('Basics'),
            _field(_firstName, 'First name', textCapitalization: TextCapitalization.words),
            _field(_lastName, 'Last name', textCapitalization: TextCapitalization.words),
            _field(_headline, 'Professional headline',
                hint: 'e.g. Final-year IT student | Flutter & Supabase'),
            _field(_interests, 'Career interests', hint: 'e.g. Mobile development, Cloud'),
            _field(_bio, 'About you', maxLines: 4,
                hint: 'A short summary recruiters will see first.'),

            SizedBox(height: AppSpace.md),
            _sectionLabel('External links'),
            _field(_github, 'GitHub', hint: 'github.com/yourname', isUrl: true),
            _field(_linkedin, 'LinkedIn', hint: 'linkedin.com/in/yourname', isUrl: true),
            _field(_website, 'Website or portfolio', hint: 'yoursite.com', isUrl: true),

            if (_error != null) ...[
              SizedBox(height: AppSpace.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: AppText.bodySm(color: AppColors.error))),
                ],
              ),
            ],

            SizedBox(height: AppSpace.xl),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onPrimary),
                    )
                  : Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
            ),
            SizedBox(height: AppSpace.xl),
          ],
        ),
      ),
    );
  }

  Widget _avatarPicker() {
    final initials = [
      _firstName.text.trim(),
      _lastName.text.trim(),
    ].where((p) => p.isNotEmpty).map((p) => p[0].toUpperCase()).join();

    ImageProvider? image;
    if (_pendingAvatar != null) {
      image = FileImage(_pendingAvatar!.file);
    } else if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      image = NetworkImage(widget.mediaService.avatarUrl(_avatarPath!));
    }

    // The whole stack is tappable, not just the badge — a 24px camera icon
    // is below the 48px minimum touch target and was the reason the badge
    // felt unresponsive even once it had a handler.
    return InkWell(
      onTap: _saving ? null : _pickAvatar,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.secondaryContainer,
            backgroundImage: image,
            child: image == null
                ? Text(
                    initials.isEmpty ? '?' : initials,
                    style: AppText.headlineLg(color: AppColors.onSecondaryContainer),
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: Icon(Icons.photo_camera_outlined,
                  size: 16, color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: EdgeInsets.only(bottom: AppSpace.sm, top: AppSpace.xs),
        child: Text(text, style: AppText.labelLg(color: AppColors.onSurfaceVariant)),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    bool isUrl = false,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: isUrl ? TextCapitalization.none : textCapitalization,
        keyboardType: isUrl ? TextInputType.url : TextInputType.text,
        autocorrect: !isUrl,
        validator: isUrl
            ? (value) => ProfileService.validateOptionalUrl(value, label)
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
