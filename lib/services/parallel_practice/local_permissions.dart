enum SessionRole { primaryTutor, coTutor, student }

void requireRole(SessionRole role, Set<SessionRole> allowed) {
  if (!allowed.contains(role)) {
    throw Exception('Forbidden action for role $role');
  }
}
