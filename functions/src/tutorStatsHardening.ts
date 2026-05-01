import * as admin from "firebase-admin";
import { onDocumentWritten, onDocumentCreated } from "firebase-functions/v2/firestore";

const db = admin.firestore();

export interface TutorStats {
  tutorId: string;
  averageRating: number;
  ratingCount: number;
  totalSessions: number;
  completedSessions: number;
  totalMinutesTaught: number;
  completionRate: number;
  responseRate: number;
  onTimeStartRate: number;
  cancellationRate: number;
  noShowRate: number;
  repeatStudentRate: number;
  averageSessionDuration: number;
  totalEarningsZar: number;
  lastUpdated: admin.firestore.Timestamp;
  subjectStats: { [subject: string]: SubjectStats };
}

export interface StudentStats {
  studentId: string;
  totalSessionsBooked: number;
  totalSessionsCompleted: number;
  totalMinutesLearned: number;
  notesSaved: number;
  subjectsStudied: string[];
  repeatTutorInteractions: number;
  attendanceRate: number;
  noShowRate: number;
  savedSessionHistory: string[];
  lastUpdated: admin.firestore.Timestamp;
}

export interface SubjectStats {
  sessions: number;
  averageRating: number;
  totalMinutes: number;
  completionRate: number;
}

export class StatsHardeningService {
  static async updateTutorStatsFromSession(sessionId: string, sessionData: any): Promise<void> {
    const tutorId = sessionData.tutorId;
    if (!tutorId) return;

    const tutorStatsRef = db.collection("tutor_stats").doc(tutorId);
    const sessionRef = db.collection("tutoring_sessions").doc(sessionId);

    await db.runTransaction(async (tx) => {
      const statsSnap = await tx.get(tutorStatsRef);
      const sessionSnap = await tx.get(sessionRef);

      if (!sessionSnap.exists) return;

      const session = sessionSnap.data()!;
      const currentStats = statsSnap.exists ? statsSnap.data()! as TutorStats : this.createEmptyTutorStats(tutorId);

      const updatedStats = this.calculateUpdatedTutorStats(currentStats, session);

      tx.set(tutorStatsRef, {
        ...updatedStats,
        lastUpdated: admin.firestore.Timestamp.now(),
      });
    });
  }

  static async updateStudentStatsFromSession(sessionId: string, sessionData: any): Promise<void> {
    const studentId = sessionData.studentId;
    if (!studentId) return;

    const studentStatsRef = db.collection("student_stats").doc(studentId);
    const sessionRef = db.collection("tutoring_sessions").doc(sessionId);

    await db.runTransaction(async (tx) => {
      const statsSnap = await tx.get(studentStatsRef);
      const sessionSnap = await tx.get(sessionRef);

      if (!sessionSnap.exists) return;

      const session = sessionSnap.data()!;
      const currentStats = statsSnap.exists ? statsSnap.data()! as StudentStats : this.createEmptyStudentStats(studentId);

      const updatedStats = this.calculateUpdatedStudentStats(currentStats, session);

      tx.set(studentStatsRef, {
        ...updatedStats,
        lastUpdated: admin.firestore.Timestamp.now(),
      });
    });
  }

  static async updateStatsFromRating(reviewId: string, reviewData: any): Promise<void> {
    const tutorId = reviewData.tutorId;
    if (!tutorId) return;

    const tutorStatsRef = db.collection("tutor_stats").doc(tutorId);

    await db.runTransaction(async (tx) => {
      const statsSnap = await tx.get(tutorStatsRef);
      if (!statsSnap.exists) return;

      const currentStats = statsSnap.data()! as TutorStats;
      const updatedStats = this.updateTutorStatsWithRating(currentStats, reviewData);

      tx.set(tutorStatsRef, {
        ...updatedStats,
        lastUpdated: admin.firestore.Timestamp.now(),
      });
    });
  }

  private static createEmptyTutorStats(tutorId: string): TutorStats {
    return {
      tutorId,
      averageRating: 0,
      ratingCount: 0,
      totalSessions: 0,
      completedSessions: 0,
      totalMinutesTaught: 0,
      completionRate: 0,
      responseRate: 0,
      onTimeStartRate: 0,
      cancellationRate: 0,
      noShowRate: 0,
      repeatStudentRate: 0,
      averageSessionDuration: 0,
      totalEarningsZar: 0,
      lastUpdated: admin.firestore.Timestamp.now(),
      subjectStats: {},
    };
  }

  private static createEmptyStudentStats(studentId: string): StudentStats {
    return {
      studentId,
      totalSessionsBooked: 0,
      totalSessionsCompleted: 0,
      totalMinutesLearned: 0,
      notesSaved: 0,
      subjectsStudied: [],
      repeatTutorInteractions: 0,
      attendanceRate: 0,
      noShowRate: 0,
      savedSessionHistory: [],
      lastUpdated: admin.firestore.Timestamp.now(),
    };
  }

  private static calculateUpdatedTutorStats(currentStats: TutorStats, session: any): TutorStats {
    const status = session.status;
    const billableMinutes = session.billableMinutes || 0;
    const earnings = session.tutorEarningZar || 0;
    const subject = session.subject || "General";

    const newStats = { ...currentStats };

    newStats.totalSessions += 1;

    if (status === "COMPLETED") {
      newStats.completedSessions += 1;
      newStats.totalMinutesTaught += billableMinutes;
      newStats.totalEarningsZar += earnings;
    }

    // Update rates
    newStats.completionRate = newStats.completedSessions / newStats.totalSessions;

    // Update subject stats
    if (!newStats.subjectStats[subject]) {
      newStats.subjectStats[subject] = {
        sessions: 0,
        averageRating: 0,
        totalMinutes: 0,
        completionRate: 0,
      };
    }

    const subjectStats = newStats.subjectStats[subject];
    subjectStats.sessions += 1;
    subjectStats.totalMinutes += billableMinutes;

    if (status === "COMPLETED") {
      subjectStats.completionRate = (subjectStats.completionRate * (subjectStats.sessions - 1) + 1) / subjectStats.sessions;
    }

    // Update average session duration
    if (newStats.completedSessions > 0) {
      newStats.averageSessionDuration = newStats.totalMinutesTaught / newStats.completedSessions;
    }

    return newStats;
  }

  private static calculateUpdatedStudentStats(currentStats: StudentStats, session: any): StudentStats {
    const status = session.status;
    const billableMinutes = session.billableMinutes || 0;
    const subject = session.subject || "General";

    const newStats = { ...currentStats };

    newStats.totalSessionsBooked += 1;

    if (status === "COMPLETED") {
      newStats.totalSessionsCompleted += 1;
      newStats.totalMinutesLearned += billableMinutes;

      if (!newStats.subjectsStudied.includes(subject)) {
        newStats.subjectsStudied.push(subject);
      }
    }

    newStats.attendanceRate = newStats.totalSessionsCompleted / newStats.totalSessionsBooked;

    return newStats;
  }

  private static updateTutorStatsWithRating(currentStats: TutorStats, review: any): TutorStats {
    const rating = review.rating10 || 0;
    const subject = review.subject || "General";

    const newStats = { ...currentStats };

    // Update overall rating
    const totalRatingPoints = newStats.averageRating * newStats.ratingCount;
    newStats.ratingCount += 1;
    newStats.averageRating = (totalRatingPoints + rating) / newStats.ratingCount;

    // Update subject rating
    if (newStats.subjectStats[subject]) {
      const subjectStats = newStats.subjectStats[subject];
      const subjectTotalRating = subjectStats.averageRating * (subjectStats.sessions - 1); // Approximation
      subjectStats.averageRating = (subjectTotalRating + rating) / subjectStats.sessions;
    }

    return newStats;
  }
}

// Update stats when sessions end
export const updateStatsOnSessionEnd = onDocumentWritten(
  "tutoring_sessions/{sessionId}",
  async (event) => {
    const sessionId = event.params.sessionId;
    const afterData = event.data?.after?.data();

    if (!afterData) return;

    const status = afterData.status;
    if (["COMPLETED", "CANCELLED", "MISSED", "NO_SHOW"].includes(status)) {
      await StatsHardeningService.updateTutorStatsFromSession(sessionId, afterData);
      await StatsHardeningService.updateStudentStatsFromSession(sessionId, afterData);
    }
  }
);

// Update stats when ratings are submitted
export const updateStatsOnRating = onDocumentCreated(
  "tutor_session_reviews/{reviewId}",
  async (event) => {
    const reviewData = event.data?.data();
    if (reviewData) {
      await StatsHardeningService.updateStatsFromRating(event.params.reviewId, reviewData);
    }
  }
);