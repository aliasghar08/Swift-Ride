import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { getGeminiModel, logger, AI_CONFIG } from '../../config/ai';
import { assertAuthenticated } from '../../middleware/auth';

const RIDER_SYSTEM_PROMPT = `
You are SwiftRide's rider assistant. Help riders with:
- Tracking their ride ("Where is my driver?")
- Understanding fares and pricing (zero commission platform, fair distance-based rates)
- Managing payment methods (Stripe card, Apple Pay, Google Pay)
- Reporting issues or lost items
- Safety features (Share My Trip, RideCheck safety checks, SOS emergency button)
Keep responses concise (1-3 sentences). Never share driver personal phone or private info.
If the user indicates an emergency, advise them to press the red SOS button immediately.
`;

const DRIVER_SYSTEM_PROMPT = `
You are SwiftRide's driver assistant. Help drivers with:
- Understanding earnings and payouts (100% earnings kept in Year 1, zero commission)
- Finding high-demand areas and peak times
- Vehicle maintenance reminders
- Subscription plans ($1/day, $15/month starting Year 2)
- Safety features (emergency SOS, RideCheck assistance)
Keep responses concise (1-3 sentences). Never share rider personal phone or private info.
`;

export interface ChatMessageInput {
  role: 'user' | 'model';
  content: string;
}

export interface ConversationalAssistantRequest {
  message: string;
  conversationId?: string;
  history?: ChatMessageInput[];
  context?: {
    activeRideId?: string;
    currentScreen?: string;
    location?: { lat: number; lng: number };
  };
}

export async function processConversation(
  userId: string,
  userRole: 'rider' | 'driver' | 'admin',
  requestData: ConversationalAssistantRequest
) {
  const { message, conversationId, history = [], context = {} } = requestData;

  if (!message || message.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Message content cannot be empty.');
  }

  logger.info({ userId, userRole, conversationId }, 'Processing AI assistant conversation');

  const systemPrompt = userRole === 'driver' ? DRIVER_SYSTEM_PROMPT : RIDER_SYSTEM_PROMPT;

  // Simple heuristic intent detection
  let detectedIntent: string | null = null;
  const lowerMsg = message.toLowerCase();
  if (lowerMsg.includes('where is my driver') || lowerMsg.includes('track') || lowerMsg.includes('status of ride')) {
    detectedIntent = 'track_ride';
  } else if (lowerMsg.includes('earning') || lowerMsg.includes('payout') || lowerMsg.includes('how much made')) {
    detectedIntent = 'show_earnings';
  } else if (lowerMsg.includes('emergency') || lowerMsg.includes('sos') || lowerMsg.includes('danger') || lowerMsg.includes('help me')) {
    detectedIntent = 'trigger_sos';
  }

  let replyText: string;

  try {
    const model = getGeminiModel(AI_CONFIG.MAX_OUTPUT_TOKENS_CHAT, systemPrompt);

    // Build chat contents including recent conversation history (max 6 messages)
    const recentHistory = history.slice(-6).map((msg) => ({
      role: msg.role === 'user' ? 'user' : 'model',
      parts: [{ text: msg.content }],
    }));

    const chatSession = model.startChat({
      history: recentHistory,
    });

    const result = await chatSession.sendMessage(message);
    replyText = result.response.text().trim();
  } catch (err: any) {
    logger.warn({ err: err?.message, userId }, 'Gemini call failed in assistant, using graceful fallback');
    if (detectedIntent === 'track_ride') {
      replyText = 'You can track your driver in real-time right on the map. Your driver will arrive shortly!';
    } else if (detectedIntent === 'show_earnings') {
      replyText = 'You keep 100% of your earnings on SwiftRide with zero commission in Year 1! Check your earnings tab for daily totals.';
    } else if (detectedIntent === 'trigger_sos') {
      replyText = 'If you feel unsafe, tap the red SOS button immediately. We notify emergency services and our 24/7 safety dispatch team.';
    } else {
      replyText = `Hello! I am your SwiftRide Assistant. I can help you track rides, check pricing, explain safety features, or resolve trip questions.`;
    }
  }

  // Persist conversation to Firestore
  const convCollection = db.collection(APP_CONSTANTS.COLLECTIONS.AI_CONVERSATIONS);
  let resolvedConversationId = conversationId;

  const now = admin.firestore.Timestamp.now();
  const newMessages = [
    { role: 'user', content: message, timestamp: now },
    { role: 'model', content: replyText, timestamp: now },
  ];

  if (resolvedConversationId) {
    const docRef = convCollection.doc(resolvedConversationId);
    await docRef.set(
      {
        userId,
        role: userRole,
        context,
        messages: admin.firestore.FieldValue.arrayUnion(...newMessages),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } else {
    const newDoc = await convCollection.add({
      userId,
      role: userRole,
      context,
      messages: newMessages,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    resolvedConversationId = newDoc.id;
  }

  return {
    conversationId: resolvedConversationId,
    reply: replyText,
    intent: detectedIntent,
    role: userRole,
    timestamp: new Date().toISOString(),
  };
}

/**
 * Callable function: conversationalAssistant
 * Enforces App Check and authenticated session.
 */
export const conversationalAssistant = onCall(
  {
    region: APP_CONSTANTS.REGION,
    enforceAppCheck: true,
    memory: '512MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    const user = await assertAuthenticated(request);
    return processConversation(user.uid, user.role, request.data || {});
  }
);
