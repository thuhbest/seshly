type AdmissionToken = {
  userId: string;
};

let globalInFlight = 0;
const userInFlight = new Map<string, number>();

export type InFlightAdmission = {
  allowed: boolean;
  globalInFlight: number;
  userInFlight: number;
  token?: AdmissionToken;
};

export function admitInFlightRequest(params: {
  userId: string;
  maxPerUser: number;
  maxGlobal: number;
}): InFlightAdmission {
  const currentUser = userInFlight.get(params.userId) ?? 0;
  if (currentUser >= params.maxPerUser || globalInFlight >= params.maxGlobal) {
    return {
      allowed: false,
      globalInFlight,
      userInFlight: currentUser,
    };
  }

  globalInFlight += 1;
  userInFlight.set(params.userId, currentUser + 1);

  return {
    allowed: true,
    globalInFlight,
    userInFlight: currentUser + 1,
    token: {userId: params.userId},
  };
}

export function releaseInFlightRequest(token?: AdmissionToken): void {
  if (!token) return;
  const currentUser = userInFlight.get(token.userId) ?? 0;
  if (currentUser <= 1) {
    userInFlight.delete(token.userId);
  } else {
    userInFlight.set(token.userId, currentUser - 1);
  }
  globalInFlight = Math.max(globalInFlight - 1, 0);
}

export function resetInFlightLimiter(): void {
  globalInFlight = 0;
  userInFlight.clear();
}
