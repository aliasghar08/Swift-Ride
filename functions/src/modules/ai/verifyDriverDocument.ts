import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { getGeminiModel, logger, AI_CONFIG } from '../../config/ai';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const DocumentTypeEnum = z.enum([
  'CNIC_FRONT',
  'CNIC_BACK',
  'DRIVING_LICENSE',
  'VEHICLE_REGISTRATION',
  'VEHICLE_FRONT',
  'VEHICLE_INTERIOR',
]);

const ExpectedDataSchema = z.object({
  fullName: z.string().optional(),
  cnicNumber: z.string().optional(),
  licenseNumber: z.string().optional(),
  vehiclePlate: z.string().optional(),
  vehicleModel: z.string().optional(),
});

const VerifyDriverDocumentSchema = z.object({
  driverId: z.string().min(1),
  documentType: DocumentTypeEnum,
  imageBase64: z.string().min(10),
  mimeType: z.string().default('image/jpeg'),
  expectedData: ExpectedDataSchema.optional(),
  downloadUrl: z.string().url().optional(),
});

export interface DocumentVerificationResult {
  documentTypeDetected: string;
  isValidDocument: boolean;
  confidence: number;
  extractedFields: {
    fullName?: string;
    idNumber?: string;
    expiryDate?: string | null;
    issueDate?: string | null;
    vehiclePlate?: string | null;
    dob?: string | null;
    gender?: 'female' | 'male' | null;
  };
  isExpired: boolean;
  isNameMatch: boolean | null;
  isNumberMatch: boolean | null;
  qualityCheck: {
    isClear: boolean;
    isTamperedOrEdited: boolean;
    glareOrObstruction: boolean;
  };
  status: 'VERIFIED' | 'NEEDS_REVIEW' | 'REJECTED';
  issues: string[];
  summary: string;
}

export const verifyDriverDocument = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false, timeoutSeconds: 60, memory: '512MiB' },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(VerifyDriverDocumentSchema, request.data);

    // Verify caller has permission (driver themselves or admin)
    if (caller.uid !== data.driverId && caller.role !== 'admin') {
      throw new HttpsError('permission-denied', 'You cannot verify documents for another driver.');
    }

    logger.info({ driverId: data.driverId, documentType: data.documentType }, 'Initiating AI driver document verification');

    // Clean base64 string if it contains data URL prefix
    let cleanBase64 = data.imageBase64;
    if (cleanBase64.includes(';base64,')) {
      cleanBase64 = cleanBase64.split(';base64,')[1];
    }
    cleanBase64 = cleanBase64.replace(/\s/g, '');

    const expected = data.expectedData || {};

    const prompt = `
You are an expert document verification and fraud prevention officer for SwiftRide in Pakistan.
Analyze the provided Pakistani document or vehicle inspection image.
Expected Document Type: ${data.documentType}
Expected Full Name: ${expected.fullName || 'Not provided'}
Expected CNIC (13 digits): ${expected.cnicNumber || 'Not provided'}
Expected License Number: ${expected.licenseNumber || 'Not provided'}
Expected Vehicle Plate: ${expected.vehiclePlate || 'Not provided'}
Expected Vehicle Model: ${expected.vehicleModel || 'Not provided'}

Tasks by Document Type:
- If CNIC_FRONT, CNIC_BACK, DRIVING_LICENSE, or VEHICLE_REGISTRATION:
  1. Identify if the document is an official Pakistani document.
  2. Read the text via OCR and extract:
     - Full Name
     - ID / Document Number (13-digit CNIC, License #, or Vehicle Reg #)
     - Expiry Date (if visible, in YYYY-MM-DD or DD/MM/YYYY)
     - Issue Date (if visible)
     - Vehicle Plate # (for Vehicle Registration)
     - Gender ('female' | 'male' | null): Read explicitly or infer from Pakistani CNIC 13th digit (even is female, odd is male).
  3. Check for quality: is it clear, readable, un-blurred, and untampered?
  4. Check if the extracted name or document number matches the expected profile.
  5. Check if the document has expired.

- If VEHICLE_FRONT:
  1. Verify if this is a real vehicle exterior front view.
  2. OCR the number plate on the bumper: does it match "${expected.vehiclePlate || ''}"?
  3. Verify that the vehicle is in roadworthy condition without major front collision damage.
  4. Extract "vehiclePlate" into extractedFields.

- If VEHICLE_INTERIOR:
  1. Verify if this is an authentic vehicle passenger cabin/seats interior.
  2. Check if the passenger seats are clean, undamaged, and safe for riders.
  3. Verify no severe tears, hazards, or obstruction.

You must respond ONLY with a valid raw JSON object (no markdown, no backticks, no code fence).
Use this exact JSON schema:
{
  "documentTypeDetected": "${data.documentType}",
  "isValidDocument": true,
  "confidence": 0.95,
  "extractedFields": {
    "fullName": "Extracted Name",
    "idNumber": "12345-1234567-1",
    "expiryDate": "2028-10-15",
    "issueDate": "2023-10-15",
    "vehiclePlate": "ABC-1234",
    "dob": null,
    "gender": "female"
  },
  "isExpired": false,
  "isNameMatch": true,
  "isNumberMatch": true,
  "qualityCheck": {
    "isClear": true,
    "isTamperedOrEdited": false,
    "glareOrObstruction": false
  },
  "status": "VERIFIED",
  "issues": [],
  "summary": "Verified successfully."
}

Rules for status:
- "VERIFIED": Valid official document or clear vehicle photo, plate/details match, confidence >= 0.80.
- "NEEDS_REVIEW": Low quality, slight discrepancy, or borderline confidence (0.60 - 0.79).
- "REJECTED": Expired, clear mismatch, fake/tampered document, or unreadable blur (confidence < 0.60).
`;

    let result: DocumentVerificationResult;

    try {
      const model = getGeminiModel(1024, 'You are a rigorous, highly accurate Pakistani document verification system. Always output valid JSON.');
      const response = await model.generateContent([
        prompt,
        {
          inlineData: {
            data: cleanBase64,
            mimeType: data.mimeType || 'image/jpeg',
          },
        },
      ]);

      const text = response.response.text().trim();
      // Clean JSON in case markdown fence is returned
      const cleanJson = text.replace(/^```json\s*/i, '').replace(/\s*```$/, '').trim();
      result = JSON.parse(cleanJson);
    } catch (err: any) {
      logger.warn({ err: err?.message, driverId: data.driverId }, 'Gemini vision call failed, queuing document for manual review');
      // Secure fallback: NEVER auto-verify when AI inspection fails or is unavailable.
      const hasValidLength = cleanBase64.length > 500;
      result = {
        documentTypeDetected: data.documentType,
        isValidDocument: false,
        confidence: hasValidLength ? 0.50 : 0.20,
        extractedFields: {
          fullName: expected.fullName,
          idNumber: expected.cnicNumber || expected.licenseNumber,
          expiryDate: null,
          issueDate: null,
          vehiclePlate: expected.vehiclePlate,
          dob: null,
        },
        isExpired: false,
        isNameMatch: null,
        isNumberMatch: null,
        qualityCheck: {
          isClear: hasValidLength,
          isTamperedOrEdited: false,
          glareOrObstruction: false,
        },
        status: 'NEEDS_REVIEW',
        issues: hasValidLength
          ? ['Automated visual inspection temporarily unavailable. Queued for manual admin verification.']
          : ['Image resolution too low or corrupt for inspection.'],
        summary: hasValidLength
          ? `${data.documentType.replace('_', ' ')} received and queued for manual verification.`
          : 'Document upload failed quality thresholds.',
      };
    }

    // Persist document record to Firestore: drivers/{driverId}/documents/{documentType}
    const docRef = db
      .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
      .doc(data.driverId)
      .collection('documents')
      .doc(data.documentType);

    await docRef.set({
      documentType: data.documentType,
      status: result.status,
      confidence: result.confidence,
      extractedFields: result.extractedFields,
      issues: result.issues,
      summary: result.summary,
      downloadUrl: data.downloadUrl || null,
      isVerified: result.status === 'VERIFIED',
      verifiedAt: result.status === 'VERIFIED' ? FieldValue.serverTimestamp() : null,
      updatedAt: FieldValue.serverTimestamp(),
      aiModel: 'gemini-3.8-flash',
    });

    // Update vehicle front/interior photo on driver profile if applicable
    if (data.downloadUrl) {
      if (data.documentType === 'VEHICLE_FRONT') {
        await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(data.driverId).set(
          { vehicle: { frontPhotoUrl: data.downloadUrl }, updatedAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
      } else if (data.documentType === 'VEHICLE_INTERIOR') {
        await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(data.driverId).set(
          { vehicle: { interiorPhotoUrl: data.downloadUrl }, updatedAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
      }
    }

    // Extract or infer gender from official documents (CNIC / Driving License)
    let detectedGender: 'female' | 'male' | null = null;
    if (result.status === 'VERIFIED') {
      const rawGender = result.extractedFields?.gender?.toLowerCase();
      if (rawGender === 'female' || rawGender === 'male') {
        detectedGender = rawGender;
      } else if (result.extractedFields?.idNumber) {
        // Pakistani CNIC format: 13 digits where the last digit is even for female, odd for male
        const digitsOnly = result.extractedFields.idNumber.replace(/\D/g, '');
        if (digitsOnly.length === 13) {
          const lastDigit = parseInt(digitsOnly.slice(-1), 10);
          detectedGender = lastDigit % 2 === 0 ? 'female' : 'male';
        }
      }
    }

    if (detectedGender) {
      await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(data.driverId).set(
        {
          gender: detectedGender,
          isGenderVerified: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(data.driverId).set(
        {
          gender: detectedGender,
          isGenderVerified: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.info({ driverId: data.driverId, detectedGender }, 'Gender successfully verified from official document');
    }

    // Check overall verification status across all documents
    const allDocsSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
      .doc(data.driverId)
      .collection('documents')
      .get();

    const docStatuses = new Map<string, string>();
    allDocsSnap.docs.forEach((d) => {
      docStatuses.set(d.id, d.data().status);
    });

    const hasCnic = docStatuses.get('CNIC_FRONT') === 'VERIFIED';
    const hasLicense = docStatuses.get('DRIVING_LICENSE') === 'VERIFIED';
    const hasReg = docStatuses.get('VEHICLE_REGISTRATION') === 'VERIFIED';

    const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(data.driverId);

    // Core legal requirements in Pakistan: CNIC, Driving License, AND Vehicle Registration
    // must ALL be verified before auto-approving driver profile!
    const allCoreDocsVerified = hasCnic && hasLicense && hasReg;

    if (allCoreDocsVerified) {
      await driverRef.update({
        isVerified: true,
        verificationStatus: 'VERIFIED',
        hasSubmittedDocuments: true,
        verificationNotes: `AI automated verification passed on ${new Date().toISOString()} via Gemini 3.8 Flash.`,
        verifiedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      logger.info({ driverId: data.driverId }, 'Driver successfully auto-verified via AI!');
    } else {
      const anyRejected = Array.from(docStatuses.values()).includes('REJECTED');
      await driverRef.update({
        hasSubmittedDocuments: true,
        verificationStatus: anyRejected ? 'REJECTED' : 'NEEDS_REVIEW',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    return {
      success: true,
      documentType: data.documentType,
      result,
      allDocumentsVerified: allCoreDocsVerified,
    };
  }
);

