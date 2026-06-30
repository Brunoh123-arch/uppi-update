/**
 * Tipos e constantes compartilhados — versão Supabase (Deno)
 * Migrado de functions/src/core/types.ts
 */

// ===== ENUMS =====

export enum OrderStatus {
  Requested = 'requested',
  NotFound = 'not_found',
  NoCloseFound = 'no_close_found',
  Found = 'found',
  DriverAccepted = 'driver_accepted',
  Arrived = 'arrived',
  WaitingForPrePay = 'waiting_for_prepay',
  WaitingForPostPay = 'waiting_for_postpay',
  Started = 'started',
  WaitingForReview = 'waiting_for_review',
  Finished = 'finished',
  RiderCanceled = 'rider_canceled',
  DriverCanceled = 'driver_canceled',
  Expired = 'expired',
  Booked = 'booked',
}

export enum DriverStatus {
  Online = 'online',
  Offline = 'offline',
  InService = 'in_service',
  WaitingDocuments = 'waiting_documents',
  PendingApproval = 'pending_approval',
  SoftReject = 'soft_reject',
  HardReject = 'hard_reject',
  Blocked = 'blocked',
}

export enum UserRole {
  Rider = 'rider',
  Driver = 'driver',
  Admin = 'admin',
  Operator = 'operator',
}

export enum PaymentMethod {
  Cash = 'cash',
  Wallet = 'wallet',
  CreditCard = 'credit_card',
  Pix = 'pix',
}

export enum TransactionType {
  RideFare = 'ride_fare',
  Commission = 'commission',
  Tip = 'tip',
  Recharge = 'recharge',
  Withdrawal = 'withdrawal',
  Refund = 'refund',
  Bonus = 'bonus',
}

// ===== INTERFACES =====

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface Waypoint {
  address: string;
  coordinates: GeoPoint;
}

export interface ServiceConfig {
  id: string;
  name: string;
  base_fare: number;
  per_km_fare: number;
  per_minute_fare: number;
  minimum_fare: number;
  cancellation_fee: number;
  max_distance_km: number;
}

// ===== HELPERS =====

/** Calcula distância entre dois pontos em metros (Haversine) */
export function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000.0;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Gera número de pedido único */
export function generateOrderNumber(): string {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).substring(2, 6);
  return `ORD-${timestamp}-${random}`.toUpperCase();
}
