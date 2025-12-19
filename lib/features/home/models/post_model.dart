class PostModel {
  final String subject;
  final String question;
  final String author;
  final String timeAgo;
  final int likes;
  final int comments;

  PostModel({
    required this.subject,
    required this.question,
    required this.author,
    required this.timeAgo,
    required this.likes,
    required this.comments,
  });
}