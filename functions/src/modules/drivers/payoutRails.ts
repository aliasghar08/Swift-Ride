import { defineSecret } from 'firebase-functions/params';

/**
 * Supported driver payout rails for the Pakistan market.
 *
 * `manual` settles out-of-band by an operator and is the only rail that can run
 * without merchant credentials. The others fail closed until their credentials
 * are configured — a payout is NEVER reported as paid when no money moved.
 */
export type PayoutRail = 'jazzcash' | 'easypaisa' | 'raast' | 'manual';

export const PAYOUT_RAILS: readonly PayoutRail[] = [
  'jazzcash',
  'easypaisa',
  'raast',
  'manual',
] as const;

// Credentials are declared here so they can be bound per-function and populated
// with `firebase functions:secrets:set <NAME>`.
export const jazzcashMerchantId = defineSecret('JAZZCASH_MERCHANT_ID');
export const jazzcashIntegritySalt = defineSecret('JAZZCASH_INTEGRITY_SALT');
export const easypaisaStoreId = defineSecret('EASYPAISA_STORE_ID');
export const easypaisaHashKey = defineSecret('EASYPAISA_HASH_KEY');
export const raastApiKey = defineSecret('RAAST_API_KEY');

export const PAYOUT_SECRETS = [
  jazzcashMerchantId,
  jazzcashIntegritySalt,
  easypaisaStoreId,
  easypaisaHashKey,
  raastApiKey,
];

export interface PayoutDispatchRequest {
  payoutId: string;
  driverId: string;
  amount: number;
  currency: string;
  /** Mobile wallet number (JazzCash/Easypaisa) or IBAN (Raast). */
  destination: string;
}

export interface PayoutDispatchResult {
  /** True only when the rail accepted the transfer instruction. */
  accepted: boolean;
  /** True when the rail is simply not configured yet (not a failure of funds). */
  configurationMissing?: boolean;
  /** Reference from the rail, when accepted. */
  railReference?: string;
  failureReason?: string;
}

function readSecret(secret: { value: () => string }): string {
  try {
    return secret.value() ?? '';
  } catch {
    return '';
  }
}

/**
 * Dispatches a payout to the selected rail.
 *
 * IMPORTANT: this returns `accepted: false` for any rail whose credentials are
 * absent. It must never return success without a real transfer instruction, and
 * callers must not mark a payout `paid` unless `accepted` is true.
 *
 * The request construction for each commercial rail needs that provider's
 * merchant integration guide (JazzCash disbursement / Easypaisa withdrawal /
 * your bank's Raast disbursement API). Those bodies are intentionally not
 * guessed here — an incorrect payment instruction is worse than an honest
 * "not configured".
 */
export async function dispatchPayout(
  rail: PayoutRail,
  request: PayoutDispatchRequest
): Promise<PayoutDispatchResult> {
  switch (rail) {
    case 'manual':
      // Settled by an operator out-of-band. The payout stays `processing` until
      // someone confirms the transfer actually landed.
      return { accepted: true, railReference: `manual:${request.payoutId}` };

    case 'jazzcash': {
      if (!readSecret(jazzcashMerchantId) || !readSecret(jazzcashIntegritySalt)) {
        return notConfigured('JazzCash', 'JAZZCASH_MERCHANT_ID', 'JAZZCASH_INTEGRITY_SALT');
      }
      return pendingIntegration('JazzCash');
    }

    case 'easypaisa': {
      if (!readSecret(easypaisaStoreId) || !readSecret(easypaisaHashKey)) {
        return notConfigured('Easypaisa', 'EASYPAISA_STORE_ID', 'EASYPAISA_HASH_KEY');
      }
      return pendingIntegration('Easypaisa');
    }

    case 'raast': {
      if (!readSecret(raastApiKey)) {
        return notConfigured('Raast', 'RAAST_API_KEY');
      }
      return pendingIntegration('Raast');
    }

    default:
      return { accepted: false, failureReason: `Unsupported payout rail: ${rail}` };
  }
}

function notConfigured(railName: string, ...secrets: string[]): PayoutDispatchResult {
  return {
    accepted: false,
    configurationMissing: true,
    failureReason:
      `${railName} payouts are not configured yet. Set ${secrets.join(', ')} via ` +
      '`firebase functions:secrets:set`, then retry. No money has moved.',
  };
}

function pendingIntegration(railName: string): PayoutDispatchResult {
  // Credentials exist but the provider's disbursement call is not implemented.
  // Fail closed: never imply a transfer happened.
  return {
    accepted: false,
    configurationMissing: true,
    failureReason:
      `${railName} credentials are present but the disbursement integration is ` +
      'not implemented yet. No money has moved.',
  };
}
