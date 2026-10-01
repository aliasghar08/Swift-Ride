import { GoogleGenerativeAI } from '@google/generative-ai';
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  base: { service: 'swiftride-ai' },
});

export const AI_CONFIG = {
  MODEL_NAME: process.env.GEMINI_MODEL || 'gemini-3.8-flash',
  MAX_OUTPUT_TOKENS_CHAT: 256,
  MAX_OUTPUT_TOKENS_INSIGHT: 512,
  TEMPERATURE: 0.7,
  CACHE_TTL_HOURS: 24,
  RATE_LIMITS: {
    CHAT_PER_HOUR: 20,
    INSIGHTS_PER_DAY: 10,
  },
};

let genAIClient: GoogleGenerativeAI | null = null;

export function getGeminiClient(): GoogleGenerativeAI {
  if (!genAIClient) {
    const apiKey = process.env.GEMINI_API_KEY || 'AIzaSy_placeholder_key_for_testing';
    genAIClient = new GoogleGenerativeAI(apiKey);
  }
  return genAIClient;
}

export function getGeminiModel(customMaxTokens?: number, systemInstruction?: string) {
  const client = getGeminiClient();
  return client.getGenerativeModel({
    model: AI_CONFIG.MODEL_NAME,
    systemInstruction,
    generationConfig: {
      maxOutputTokens: customMaxTokens || AI_CONFIG.MAX_OUTPUT_TOKENS_INSIGHT,
      temperature: AI_CONFIG.TEMPERATURE,
    },
  });
}
