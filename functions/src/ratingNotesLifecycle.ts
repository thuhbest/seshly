import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

const db = admin.firestore();

export interface SessionNotes {
  sessionId: string;
  studentId: string;
  tutorId: string;
  subject: string;
  notes: SessionNote[];
  finalSummary?: string;
  aiCleanNotes?: string;
  createdAt: admin.firestore.Timestamp;
  finalizedAt?: admin.firestore.Timestamp;
  isFinalized: boolean;
}

export interface SessionNote {
  id: string;
  type: "board" | "annotation" | "correction" | "summary" | "ai_generated";
  content: string;
  timestamp: admin.firestore.Timestamp;
  author: "student" | "tutor" | "ai";
}

export interface RatingEligibility {
  sessionId: string;
  studentId: string;
  tutorId: string;
  subject: string;
  billableMinutes: number;
  qualifiesForGoldTick: boolean;
  createdAt: admin.firestore.Timestamp;
  expiresAt: admin.firestore.Timestamp;
  isUsed: boolean;
}

export interface SessionRating {
  sessionId: string;
  studentId: string;
  tutorId: string;
  rating: number; // 1-10
  reviewText?: string;
  tags?: string[];
  isAnonymous: boolean;
  createdAt: admin.firestore.Timestamp;
  qualifiesForGoldTick: boolean;
}

export class RatingNotesLifecycleService {
  static async createRatingEligibilityOnSessionEnd(sessionId: string): Promise<void> {
    const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
    const sessionSnap = await sessionRef.get();

    if (!sessionSnap.exists) return;

    const sessionData = sessionSnap.data()!;
    if (sessionData.status !== "COMPLETED") return;

    const eligibility: RatingEligibility = {
      sessionId,
      studentId: sessionData.studentId,
      tutorId: sessionData.tutorId,
      subject: sessionData.subject || "General",
      billableMinutes: sessionData.billableMinutes || 0,
      qualifiesForGoldTick: (sessionData.billableMinutes || 0) >= 15,
      createdAt: admin.firestore.Timestamp.now(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000 // 30 days
      ),
      isUsed: false,
    };

    await db.collection("rating_eligibilities").doc(sessionId).set(eligibility);
  }

  static async finalizeSessionNotes(sessionId: string, studentId: string): Promise<void> {
    const notesRef = db.collection("session_notes").doc(sessionId);
    const sessionRef = db.collection("tutoring_sessions").doc(sessionId);

    await db.runTransaction(async (tx) => {
      const notesSnap = await tx.get(notesRef);
      const sessionSnap = await tx.get(sessionRef);

      if (!sessionSnap.exists) return;

      const sessionData = sessionSnap.data()!;
      if (sessionData.studentId !== studentId) {
        throw new Error("Unauthorized to finalize notes");
      }

      let notes: SessionNote[] = [];
      if (notesSnap.exists) {
        const notesData = notesSnap.data()!;
        notes = notesData.notes || [];
      }

      // Generate final summary
      const finalSummary = this.generateFinalSummary(notes);
      const aiCleanNotes = await this.generateAICleanNotes(notes);

      const finalizedNotes: SessionNotes = {
        sessionId,
        studentId: sessionData.studentId,
        tutorId: sessionData.tutorId,
        subject: sessionData.subject || "General",
        notes,
        finalSummary,
        aiCleanNotes,
        createdAt: notesSnap.exists ? notesSnap.data()!.createdAt : admin.firestore.Timestamp.now(),
        finalizedAt: admin.firestore.Timestamp.now(),
        isFinalized: true,
      };

      tx.set(notesRef, finalizedNotes);

      // Update student's saved notes count
      const studentStatsRef = db.collection("student_stats").doc(studentId);
      tx.set(studentStatsRef, {
        notesSaved: admin.firestore.FieldValue.increment(1),
        lastUpdated: admin.firestore.Timestamp.now(),
      }, { merge: true });
    });
  }

  static async submitSessionRating(sessionId: string, studentId: string, ratingData: {
    rating: number;
    reviewText?: string;
    tags?: string[];
    isAnonymous?: boolean;
  }): Promise<void> {
    // Check eligibility
    const eligibilityRef = db.collection("rating_eligibilities").doc(sessionId);
    const eligibilitySnap = await eligibilityRef.get();

    if (!eligibilitySnap.exists) {
      throw new Error("Not eligible to rate this session");
    }

    const eligibility = eligibilitySnap.data() as RatingEligibility;
    if (eligibility.studentId !== studentId || eligibility.isUsed) {
      throw new Error("Invalid rating submission");
    }

    if (ratingData.rating < 1 || ratingData.rating > 10) {
      throw new Error("Rating must be between 1 and 10");
    }

    const rating: SessionRating = {
      sessionId,
      studentId,
      tutorId: eligibility.tutorId,
      rating: ratingData.rating,
      reviewText: ratingData.reviewText,
      tags: ratingData.tags || [],
      isAnonymous: ratingData.isAnonymous || false,
      createdAt: admin.firestore.Timestamp.now(),
      qualifiesForGoldTick: eligibility.qualifiesForGoldTick,
    };

    await db.runTransaction(async (tx) => {
      // Create rating
      const ratingRef = db.collection("session_ratings").doc(sessionId);
      tx.set(ratingRef, rating);

      // Mark eligibility as used
      tx.update(eligibilityRef, { isUsed: true });

      // Update session with rating
      const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
      tx.set(sessionRef, {
        rating: ratingData.rating,
        reviewText: ratingData.reviewText,
        ratedAt: admin.firestore.Timestamp.now(),
      }, { merge: true });
    });
  }

  static async saveSessionNote(sessionId: string, userId: string, note: Omit<SessionNote, "id" | "timestamp">): Promise<void> {
    const notesRef = db.collection("session_notes").doc(sessionId);
    const sessionRef = db.collection("tutoring_sessions").doc(sessionId);

    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      throw new Error("Session not found");
    }

    const sessionData = sessionSnap.data()!;
    if (sessionData.studentId !== userId && sessionData.tutorId !== userId) {
      throw new Error("Unauthorized to save notes");
    }

    const author = sessionData.studentId === userId ? "student" : "tutor";

    await db.runTransaction(async (tx) => {
      const notesSnap = await tx.get(notesRef);

      let existingNotes: SessionNote[] = [];
      if (notesSnap.exists) {
        existingNotes = notesSnap.data()!.notes || [];
      }

      const newNote: SessionNote = {
        ...note,
        id: `note_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        timestamp: admin.firestore.Timestamp.now(),
        author,
      };

      const updatedNotes = [...existingNotes, newNote];

      tx.set(notesRef, {
        sessionId,
        studentId: sessionData.studentId,
        tutorId: sessionData.tutorId,
        subject: sessionData.subject || "General",
        notes: updatedNotes,
        createdAt: notesSnap.exists ? notesSnap.data()!.createdAt : admin.firestore.Timestamp.now(),
        isFinalized: false,
      }, { merge: true });
    });
  }

  private static generateFinalSummary(notes: SessionNote[]): string {
    const summaries = notes
      .filter(note => note.type === "summary")
      .map(note => note.content);

    if (summaries.length === 0) {
      return "Session completed. No summary provided.";
    }

    return summaries.join("\n\n");
  }

  private static async generateAICleanNotes(notes: SessionNote[]): Promise<string> {
    // Placeholder for AI cleaning - in real implementation, call AI service
    const allContent = notes.map(note => note.content).join("\n");
    return `Cleaned notes: ${allContent.substring(0, 500)}...`;
  }
}

// Create rating eligibility when session completes
export const createRatingEligibilityOnSessionComplete = onDocumentWritten(
  "tutoring_sessions/{sessionId}",
  async (event) => {
    const afterData = event.data?.after?.data();
    if (afterData?.status === "COMPLETED") {
      await RatingNotesLifecycleService.createRatingEligibilityOnSessionEnd(event.params.sessionId);
    }
  }
);

// Auto-finalize notes when session ends (if not already finalized)
export const autoFinalizeNotesOnSessionEnd = onDocumentWritten(
  "tutoring_sessions/{sessionId}",
  async (event) => {
    const sessionId = event.params.sessionId;
    const afterData = event.data?.after?.data();

    if (afterData?.status === "COMPLETED") {
      const notesRef = db.collection("session_notes").doc(sessionId);
      const notesSnap = await notesRef.get();

      if (notesSnap.exists && !notesSnap.data()!.isFinalized) {
        // Auto-finalize with student ID from session
        await RatingNotesLifecycleService.finalizeSessionNotes(sessionId, afterData.studentId);
      }
    }
  }
);