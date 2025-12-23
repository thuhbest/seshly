import 'package:flutter/material.dart';
import '../widgets/attachment_button.dart';

class NewQuestionView extends StatefulWidget {
  const NewQuestionView({super.key});

  @override
  State<NewQuestionView> createState() => _NewQuestionViewState();
}

class _NewQuestionViewState extends State<NewQuestionView> {
  String? selectedSubject;
  bool isCustomSubject = false;
  final TextEditingController _customSubjectController = TextEditingController();
  final List<String> subjects = [
    "Mathematics", "Physics", "Chemistry", "Biology", "Computer Science", "Engineering"
  ];

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("New Question", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: backgroundColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Post", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("What's your question?", 
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            // Question Input
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: const TextField(
                maxLines: 6,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Describe your question in detail... The more context you provide, the better answers you'll get!",
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text("0/500 characters", style: TextStyle(color: Colors.white38, fontSize: 12)),
            
            const SizedBox(height: 30),
            const Text("Select Subject", 
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            // Subject Chips
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...subjects.map((sub) => _subjectChip(sub)),
                _subjectChip("Other", isOther: true),
              ],
            ),

            if (isCustomSubject) ...[
              const SizedBox(height: 15),
              TextField(
                controller: _customSubjectController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Type your subject here...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: cardColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],

            const SizedBox(height: 30),
            const Text("Add Attachments (Optional)", 
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            const Row(
              children: [
                AttachmentButton(icon: Icons.image_outlined, label: "Image"),
                SizedBox(width: 15),
                AttachmentButton(icon: Icons.camera_alt_outlined, label: "Camera"),
                SizedBox(width: 15),
                AttachmentButton(icon: Icons.link, label: "Link"),
              ],
            ),

            const SizedBox(height: 40),
            
            // AI Help Box
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: tealAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: tealAccent.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: tealAccent, size: 20),
                      const SizedBox(width: 10),
                      const Text("Need help formulating your question?", 
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Sesh AI can help you articulate your question better for more accurate answers.",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Ask Sesh to help →", 
                      style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectChip(String label, {bool isOther = false}) {
    bool isSelected = selectedSubject == label;
    const Color tealAccent = Color(0xFF00C09E);

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedSubject = label;
          isCustomSubject = isOther;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tealAccent : const Color(0xFF1E243A).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? tealAccent : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label, 
          style: TextStyle(
            color: isSelected ? const Color(0xFF0F142B) : Colors.white70, 
            fontWeight: FontWeight.bold,
            fontSize: 13
          )),
      ),
    );
  }
}