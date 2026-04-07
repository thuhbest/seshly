import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

const db = admin.firestore();

export interface TutorSearchProfile {
  tutorId: string;
  displayName: string;
  organizationName?: string;
  organizationId?: string;
  subjects: string[];
  mainSubjects: string[];
  minorSubjects: string[];
  baseRatePerMinuteZar: number;
  studentRatePerMinuteZar: number;
  availability: "offline" | "accepting" | "after_current";
  isOnline: boolean;
  ratingAverage: number;
  ratingCount: number;
  completedSessions: number;
  totalMinutesTaught: number;
  completionRate: number;
  responseRate: number;
  onTimeStartRate: number;
  repeatStudentRate: number;
  cancellationRate: number;
  noShowRate: number;
  averageSessionDuration: number;
  lastActiveAt: admin.firestore.Timestamp;
  searchScore: number;
  searchIndex: string[];
  isActive: boolean;
  goldTickQualified: boolean;
  organizationVerified: boolean;
}

export class TutorSearchRankingService {
  static async updateTutorSearchProfile(tutorId: string): Promise<void> {
    const tutorRef = db.collection("users").doc(tutorId);
    const tutorSnap = await tutorRef.get();

    if (!tutorSnap.exists) {
      return;
    }

    const tutorData = tutorSnap.data()!;

    // Get performance stats
    const performance = tutorData.performance || {};
    const organization = tutorData.organization || {};

    // Calculate rates
    const baseRate = Math.max(4, tutorData.tutorRatePerMinute || 4); // Min R4
    const studentRate = baseRate * 1.2; // 20% markup

    // Calculate search score
    const searchScore = this.calculateSearchScore({
      ratingAverage: performance.ratingAverage || 0,
      ratingCount: performance.ratingCount || 0,
      completedSessions: performance.completedSessions || 0,
      completionRate: performance.completionRate || 0,
      responseRate: performance.responseRate || 0,
      onTimeStartRate: performance.onTimeStartRate || 0,
      repeatStudentRate: performance.repeatStudentRate || 0,
      cancellationRate: performance.cancellationRate || 0,
      noShowRate: performance.noShowRate || 0,
      isOnline: tutorData.isOnline || false,
      availability: tutorData.availability || "offline",
      goldTickQualified: tutorData.goldTickQualified || false,
      organizationVerified: organization.verified || false,
      lastActiveAt: tutorData.lastActiveAt,
    });

    // Build search index
    const searchIndex = this.buildSearchIndex(tutorData, organization);

    const searchProfile: TutorSearchProfile = {
      tutorId,
      displayName: tutorData.displayName || tutorData.fullName || "Tutor",
      organizationName: organization.name,
      organizationId: organization.id,
      subjects: [...(tutorData.mainSubjects || []), ...(tutorData.minorSubjects || [])],
      mainSubjects: tutorData.mainSubjects || [],
      minorSubjects: tutorData.minorSubjects || [],
      baseRatePerMinuteZar: baseRate,
      studentRatePerMinuteZar: studentRate,
      availability: tutorData.availability || "offline",
      isOnline: tutorData.isOnline || false,
      ratingAverage: performance.ratingAverage || 0,
      ratingCount: performance.ratingCount || 0,
      completedSessions: performance.completedSessions || 0,
      totalMinutesTaught: performance.totalMinutesTaught || 0,
      completionRate: performance.completionRate || 0,
      responseRate: performance.responseRate || 0,
      onTimeStartRate: performance.onTimeStartRate || 0,
      repeatStudentRate: performance.repeatStudentRate || 0,
      cancellationRate: performance.cancellationRate || 0,
      noShowRate: performance.noShowRate || 0,
      averageSessionDuration: performance.averageSessionDuration || 0,
      lastActiveAt: tutorData.lastActiveAt || admin.firestore.Timestamp.now(),
      searchScore,
      searchIndex,
      isActive: tutorData.tutorStatus === "active" || tutorData.tutorStatus === "approved",
      goldTickQualified: tutorData.goldTickQualified || false,
      organizationVerified: organization.verified || false,
    };

    await db.collection("tutor_search_profiles").doc(tutorId).set(searchProfile);
  }

  static calculateSearchScore(params: {
    ratingAverage: number;
    ratingCount: number;
    completedSessions: number;
    completionRate: number;
    responseRate: number;
    onTimeStartRate: number;
    repeatStudentRate: number;
    cancellationRate: number;
    noShowRate: number;
    isOnline: boolean;
    availability: "offline" | "accepting" | "after_current";
    goldTickQualified: boolean;
    organizationVerified: boolean;
    lastActiveAt: admin.firestore.Timestamp;
  }): number {
    let score = 0;

    // Performance factors (40%)
    score += Math.min(params.ratingAverage * 10, 50) * 0.4; // Max 20 points
    score += Math.min(params.ratingCount / 10, 10) * 0.4; // Max 4 points
    score += Math.min(params.completedSessions / 50, 10) * 0.4; // Max 4 points
    score += params.completionRate * 4; // Max 4 points
    score += params.responseRate * 4; // Max 4 points
    score += params.onTimeStartRate * 4; // Max 4 points
    score += params.repeatStudentRate * 4; // Max 4 points

    // Availability factors (30%)
    if (params.isOnline) score += 15;
    if (params.availability === "accepting") score += 10;
    else if (params.availability === "after_current") score += 5;

    // Quality badges (20%)
    if (params.goldTickQualified) score += 10;
    if (params.organizationVerified) score += 10;

    // Freshness factor (10%)
    const daysSinceActive = (Date.now() - params.lastActiveAt.toMillis()) / (1000 * 60 * 60 * 24);
    score += Math.max(0, 10 - daysSinceActive); // Max 10 points, decays with inactivity

    // Penalties
    score -= params.cancellationRate * 20; // Up to -20 points
    score -= params.noShowRate * 30; // Up to -30 points

    // Fair exposure for new tutors
    if (params.completedSessions < 5) {
      score += 15; // Boost new tutors
    }

    return Math.max(0, score);
  }

  static buildSearchIndex(tutorData: any, organization: any): string[] {
    const index: string[] = [];

    // Add name variations
    const name = tutorData.displayName || tutorData.fullName || "";
    index.push(name.toLowerCase());
    index.push(...name.toLowerCase().split(' '));

    // Add subjects
    index.push(...(tutorData.mainSubjects || []).map((s: string) => s.toLowerCase()));
    index.push(...(tutorData.minorSubjects || []).map((s: string) => s.toLowerCase()));

    // Add organization
    if (organization.name) {
      index.push(organization.name.toLowerCase());
    }

    return [...new Set(index)]; // Remove duplicates
  }

  static async searchTutors(query: {
    subject?: string;
    maxPrice?: number;
    availability?: string[];
    minRating?: number;
    limit?: number;
  }): Promise<TutorSearchProfile[]> {
    let q = db.collection("tutor_search_profiles")
      .where("isActive", "==", true)
      .orderBy("searchScore", "desc");

    if (query.subject) {
      q = q.where("subjects", "array-contains", query.subject.toLowerCase());
    }

    if (query.maxPrice) {
      q = q.where("studentRatePerMinuteZar", "<=", query.maxPrice);
    }

    if (query.minRating) {
      q = q.where("ratingAverage", ">=", query.minRating);
    }

    if (query.availability && query.availability.length > 0) {
      q = q.where("availability", "in", query.availability);
    }

    const limit = query.limit || 20;
    const snap = await q.limit(limit).get();

    return snap.docs.map(doc => doc.data() as TutorSearchProfile);
  }
}

// Auto-update search profiles when tutor data changes
export const updateTutorSearchProfileOnChange = onDocumentWritten(
  "users/{tutorId}",
  async (event) => {
    const tutorId = event.params.tutorId;
    await TutorSearchRankingService.updateTutorSearchProfile(tutorId);
  }
);

// Auto-update search profiles when performance changes
export const updateTutorSearchProfileOnPerformanceChange = onDocumentWritten(
  "tutor_performance/{tutorId}",
  async (event) => {
    const tutorId = event.params.tutorId;
    await TutorSearchRankingService.updateTutorSearchProfile(tutorId);
  }
);