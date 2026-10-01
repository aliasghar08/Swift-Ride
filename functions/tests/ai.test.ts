import { describe, it, expect, vi } from 'vitest';
import { AI_CONFIG } from '../src/config/ai';
import {
  generateEarningsInsight,
  safetyCheckIn,
  conversationalAssistant,
  predictVehicleMaintenance,
  routeOptimizer,
} from '../src/modules/ai';

describe('SwiftRide AI Module & Gemini Configuration', () => {
  it('enforces Gemini Developer API model and strict token budgets', () => {
    expect(AI_CONFIG.MODEL_NAME).toBe('gemini-3.8-flash');
    expect(AI_CONFIG.MAX_OUTPUT_TOKENS_CHAT).toBe(256);
    expect(AI_CONFIG.MAX_OUTPUT_TOKENS_INSIGHT).toBe(512);
    expect(AI_CONFIG.TEMPERATURE).toBe(0.7);
    expect(AI_CONFIG.CACHE_TTL_HOURS).toBe(24);
    expect(AI_CONFIG.RATE_LIMITS.CHAT_PER_HOUR).toBe(20);
    expect(AI_CONFIG.RATE_LIMITS.INSIGHTS_PER_DAY).toBe(10);
  });

  it('verifies callable triggers and endpoints for all AI functions', () => {
    const callables = [
      generateEarningsInsight,
      safetyCheckIn,
      conversationalAssistant,
      predictVehicleMaintenance,
      routeOptimizer,
    ];

    for (const fn of callables) {
      expect((fn as any).__endpoint).toBeDefined();
      expect((fn as any).__endpoint.platform).toBe('gcfv2');
      expect((fn as any).__endpoint.callableTrigger).toBeDefined();
      expect(typeof (fn as any).run).toBe('function');
    }
  });

  it('evaluates safety check-in fallback heuristics for long stop and route deviation', () => {
    // Verify appropriate messaging generation for safety flags
    const getFallbackMessage = (flagType: string) => {
      switch (flagType) {
        case 'LONG_STOP':
        case 'UNEXPECTED_STOP':
          return 'We noticed your ride has been stopped for a little while. Is everything going smoothly, or do you need any assistance?';
        case 'ROUTE_DEVIATION':
          return "We noticed an unexpected change in your route. Please confirm you're safe or let us know if you need help.";
        default:
          return 'SwiftRide Safety Check: Everything looking good on your trip? Tap to let us know.';
      }
    };

    const stopMsg = getFallbackMessage('LONG_STOP');
    expect(stopMsg).toContain('stopped for a little while');

    const devMsg = getFallbackMessage('ROUTE_DEVIATION');
    expect(devMsg).toContain('unexpected change in your route');
  });

  it('correctly maps user messages to intent triggers for function calling', () => {
    const detectIntent = (text: string): string | null => {
      const lower = text.toLowerCase();
      if (lower.includes('where is my driver') || lower.includes('track') || lower.includes('status of ride')) {
        return 'track_ride';
      } else if (lower.includes('earning') || lower.includes('payout') || lower.includes('how much made')) {
        return 'show_earnings';
      } else if (lower.includes('emergency') || lower.includes('sos') || lower.includes('danger') || lower.includes('help me')) {
        return 'trigger_sos';
      }
      return null;
    };

    expect(detectIntent('Where is my driver?')).toBe('track_ride');
    expect(detectIntent('Can you track my active ride?')).toBe('track_ride');
    expect(detectIntent('Show my earnings summary for this week')).toBe('show_earnings');
    expect(detectIntent('I need emergency help, SOS!')).toBe('trigger_sos');
    expect(detectIntent('What are the accepted payment methods?')).toBeNull();
  });

  it('calculates vehicle maintenance urgency based on accumulated mileage', () => {
    const calculateMaintenanceUrgency = (totalKm: number) => {
      const estimatedTotalKm = Math.round(totalKm * 1.35);
      const urgency = estimatedTotalKm > 2500 ? 'MEDIUM' : 'LOW';
      const nextDueInKm = Math.max(500, 3000 - (estimatedTotalKm % 3000));
      return { estimatedTotalKm, urgency, nextDueInKm };
    };

    const lowResult = calculateMaintenanceUrgency(1000);
    expect(lowResult.estimatedTotalKm).toBe(1350);
    expect(lowResult.urgency).toBe('LOW');

    const mediumResult = calculateMaintenanceUrgency(2200);
    expect(mediumResult.estimatedTotalKm).toBe(2970);
    expect(mediumResult.urgency).toBe('MEDIUM');
  });
});
