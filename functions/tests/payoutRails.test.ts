import { describe, expect, it } from 'vitest';
import { dispatchPayout, type PayoutRail } from '../src/modules/drivers/payoutRails';

const sampleRequest = {
  payoutId: 'payout_test_1',
  driverId: 'driver_test_1',
  amount: 1500,
  currency: 'PKR',
  destination: '03001234567',
};

describe('dispatchPayout', () => {
  it('never reports success for a rail without credentials', async () => {
    // This is the property that matters: an unconfigured rail must fail closed.
    // The previous implementation fabricated `payout_sim_<ts>` and recorded the
    // payout as "succeeded" without moving any money.
    for (const rail of ['jazzcash', 'easypaisa', 'raast'] as PayoutRail[]) {
      const result = await dispatchPayout(rail, sampleRequest);

      expect(result.accepted, `${rail} must not accept without credentials`).toBe(false);
      expect(result.configurationMissing).toBe(true);
      expect(result.failureReason).toBeTruthy();
      expect(result.railReference).toBeUndefined();
    }
  });

  it('treats manual settlement as accepted but not settled', async () => {
    const result = await dispatchPayout('manual', sampleRequest);

    // Accepted means "instructions recorded"; the payout stays `processing`
    // until an operator confirms the transfer actually landed.
    expect(result.accepted).toBe(true);
    expect(result.railReference).toContain('manual');
  });

  it('rejects an unknown rail', async () => {
    const result = await dispatchPayout('crypto' as PayoutRail, sampleRequest);

    expect(result.accepted).toBe(false);
    expect(result.failureReason).toContain('crypto');
  });
});
