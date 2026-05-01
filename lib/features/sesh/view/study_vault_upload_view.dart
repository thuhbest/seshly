import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:seshly/access/app_access.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/community_backend_service.dart';
import 'package:seshly/services/study_vault_service.dart';
import 'package:seshly/widgets/pressable_scale.dart';
import 'package:seshly/widgets/responsive.dart';

class StudyVaultUploadView extends StatefulWidget {
  const StudyVaultUploadView({super.key});

  @override
  State<StudyVaultUploadView> createState() => _StudyVaultUploadViewState();
}

class _StudyVaultUploadViewState extends State<StudyVaultUploadView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _instituteController = TextEditingController();
  final TextEditingController _courseNameController = TextEditingController();
  final TextEditingController _moduleNameController = TextEditingController();
  final TextEditingController _moduleCodeController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  String _selectedType = 'Notes';
  String _accessType = 'free';
  Uint8List? _selectedBytes;
  String? _selectedFileName;
  bool _isUploading = false;
  final CommunityBackendService _backend = CommunityBackendService.instance;

  bool get _isPaid => _accessType == 'paid';
  int get _priceZar => int.tryParse(_priceController.text.trim()) ?? 0;
  int get _platformFeeZar => StudyVaultService.platformFeeFromPrice(_priceZar);
  int get _sellerNetZar => StudyVaultService.sellerNetFromPrice(_priceZar);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _instituteController.dispose();
    _courseNameController.dispose();
    _moduleNameController.dispose();
    _moduleCodeController.dispose();
    _yearController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _readFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    final stream = file.readStream;
    if (stream == null) return null;
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
      withReadStream: true,
    );
    if (result == null) return;
    final picked = result.files.single;
    final bytes = await _readFileBytes(picked);
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected file.')),
      );
      return;
    }
    setState(() {
      _selectedBytes = bytes;
      _selectedFileName = picked.name;
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = picked.name.replaceAll('.pdf', '');
      }
    });
  }

  Future<void> _handleUpload() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (!_formKey.currentState!.validate() || _selectedBytes == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Select a PDF and complete the required fields.'),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You need to be signed in to upload.')),
      );
      return;
    }

    if (_isPaid && _priceZar <= 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter a valid price for paid StudyVault resources.'),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final fileName =
          'study_vault/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putData(
        _selectedBytes!,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final url = await ref.getDownloadURL();

      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final moduleCode = _moduleCodeController.text.trim().toUpperCase();
      final moduleName = _moduleNameController.text.trim();
      final courseName = _courseNameController.text.trim();
      final institute = _instituteController.text.trim();
      final academicYear = _yearController.text.trim();

      await _backend.createStudyVaultResource(<String, dynamic>{
        'title': title,
        'description': description,
        'subject': moduleCode,
        'moduleCode': moduleCode,
        'moduleName': moduleName,
        'courseName': courseName,
        'institute': institute,
        'academicYear': academicYear,
        'resourceType': _selectedType,
        'accessType': _accessType,
        'priceZar': _isPaid ? _priceZar : 0,
        'fileUrl': url,
        'filePath': ref.fullPath,
        'fileName': _selectedFileName,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isPaid
                ? 'Paid resource published to StudyVault.'
                : 'Free resource published to StudyVault.',
          ),
        ),
      );
      navigator.pop();
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'study_vault',
        source: 'create_study_vault_resource',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppErrorService.instance.userMessageFor(
              error,
              fallback: 'Upload failed. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    final bool hasFile = _selectedBytes != null;

    if (!AccessController.can(context, AppCapability.viewStudyVault)) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('StudyVault'),
        ),
        body: const ResponsiveCenter(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'StudyVault uploads require a full account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Publish To StudyVault'),
      ),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildHeroCard(tealAccent, cardColor),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Resource file',
                subtitle: 'Upload the PDF learners will unlock or open.',
                child: PressableScale(
                  onTap: _pickFile,
                  borderRadius: BorderRadius.circular(20),
                  pressedScale: 0.98,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: hasFile ? tealAccent : Colors.white12,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.picture_as_pdf_rounded,
                          color: hasFile ? tealAccent : Colors.white24,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasFile
                              ? (_selectedFileName ?? 'PDF selected')
                              : 'Tap to select PDF',
                          style: TextStyle(
                            color: hasFile ? Colors.white : Colors.white24,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hasFile
                              ? 'File ready for publishing'
                              : 'Only PDF files are supported right now',
                          style: TextStyle(
                            color: hasFile ? Colors.white54 : Colors.white30,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _SectionCard(
                title: 'Resource details',
                subtitle:
                    'Make the value obvious before someone opens or buys it.',
                child: Column(
                  children: [
                    _buildField(
                      'Title',
                      _titleController,
                      'e.g. Calculus 2 exam prep notes',
                    ),
                    _buildField(
                      'Description',
                      _descriptionController,
                      'What does the resource cover? Include value, level, and what a buyer or learner can expect.',
                      minLines: 3,
                      maxLines: 4,
                    ),
                    _buildDropdown(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Pricing',
                subtitle: 'Choose whether this goes out free or paid.',
                child: Column(
                  children: [
                    _buildAccessTypeSelector(),
                    if (_isPaid) ...[
                      _buildField(
                        'Price (ZAR)',
                        _priceController,
                        'e.g. 49',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                      _buildCommissionCard(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Academic context',
                subtitle: 'This is what makes discovery and search accurate.',
                child: Column(
                  children: [
                    _buildField(
                      'Institute / University',
                      _instituteController,
                      'e.g. University of Cape Town',
                    ),
                    _buildField(
                      'Course Name',
                      _courseNameController,
                      'e.g. BSc Computer Science',
                    ),
                    _buildField(
                      'Module Name',
                      _moduleNameController,
                      'e.g. Algorithms and Data Structures',
                    ),
                    _buildField(
                      'Module Code',
                      _moduleCodeController,
                      'e.g. CSC2001F',
                    ),
                    _buildField(
                      'Academic Year',
                      _yearController,
                      'e.g. 2026',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Publish to StudyVault',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPaid
                          ? 'You are publishing a paid academic resource. Learners will see the public price and your seller split will be tracked automatically.'
                          : 'You are publishing a free academic resource. Learners will be able to open it immediately.',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isUploading ? null : _handleUpload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: backgroundColor,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0F142B),
                              ),
                            )
                          : const Text(
                              'Publish To StudyVault',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    int minLines = 1,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          onChanged: onChanged,
          validator: (value) {
            if ((value ?? '').trim().isEmpty) return 'Required';
            return null;
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF1E243A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resource Type',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E243A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedType,
              dropdownColor: const Color(0xFF1E243A),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: StudyVaultService.resourceTypes
                  .map(
                    (type) => DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedType = value ?? _selectedType),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildAccessTypeSelector() {
    Widget option({
      required String value,
      required String title,
      required String subtitle,
    }) {
      final bool selected = _accessType == value;
      return Expanded(
        child: PressableScale(
          onTap: () => setState(() => _accessType = value),
          borderRadius: BorderRadius.circular(16),
          pressedScale: 0.98,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF00C09E).withValues(alpha: 0.12)
                  : const Color(0xFF1E243A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? const Color(0xFF00C09E) : Colors.white10,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? const Color(0xFF00C09E) : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pricing Model',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            option(
              value: 'free',
              title: 'Free',
              subtitle: 'Anyone can open this academic resource immediately.',
            ),
            const SizedBox(width: 12),
            option(
              value: 'paid',
              title: 'Paid',
              subtitle: 'You set the public price and Seshly keeps 20%.',
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCommissionCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seshly commission',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'You set the public price. Seshly keeps 20% on paid content and you receive 80%.',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            'Learner pays: R$_priceZar • Seshly: R$_platformFeeZar • You receive: R$_sellerNetZar',
            style: const TextStyle(
              color: Color(0xFF00C09E),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(Color tealAccent, Color cardColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tealAccent.withValues(alpha: 0.16),
            cardColor.withValues(alpha: 0.95),
            const Color(0xFF111A2C),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _UploadHeroChip(label: 'Academic resources only'),
          SizedBox(height: 14),
          Text(
            'Publish to StudyVault',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Upload free or paid notes, books, past papers, and question banks. Paid uploads keep 80% for the uploader while Seshly keeps 20%.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _UploadHeroChip extends StatelessWidget {
  const _UploadHeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFFD670),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
