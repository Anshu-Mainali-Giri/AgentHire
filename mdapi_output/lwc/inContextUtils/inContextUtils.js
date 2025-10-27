/**
 * inContextUtils.js
 *
 * Utility helper for extracting the `recordId` from Salesforce's CurrentPageReference.
 * 
 * ⚡ WHY DO WE NEED THIS?
 * -----------------------
 * When overriding standard Salesforce buttons (like "New" or "Edit") with an LWC,
 * Salesforce does NOT always pass the `recordId` directly in `pageRef.state.recordId`.
 *
 * Instead:
 *   - For "New" actions, there may be no recordId at all.
 *   - For "Edit" actions, the recordId is often embedded inside a Base64-encoded field
 *     called `inContextOfRef`.
 *
 * This utility:
 *   1. First tries to read `recordId` directly (in case Salesforce provided it).
 *   2. Falls back to `c__recordId` (used sometimes when navigating with custom params).
 *   3. If still not found, decodes the Base64 string inside `inContextOfRef`
 *      to extract the recordId from its JSON payload.
 *
 * By centralizing this logic:
 *   - All LWCs can share the same reliable way to get recordId.
 *   - You don’t need to rewrite the same base64 decoding logic everywhere.
 *
 * USAGE:
 *   import { getRecordIdFromPageRef } from 'c/inContextUtils';
 *
 *   @wire(CurrentPageReference)
 *   getPageRef(pageRef) {
 *       this.recordId = getRecordIdFromPageRef(pageRef);
 *   }
 */

export function getRecordIdFromPageRef(pageRef) {
    if (!pageRef?.state) {
        return null;
    }

    // 1. Check if Salesforce gave us recordId directly
    let recordId = pageRef.state.recordId || pageRef.state.c__recordId || null;

    // 2. If not, check the encoded context (inContextOfRef)
    if (!recordId && pageRef.state.inContextOfRef) {
        try {
            let base64Context = pageRef.state.inContextOfRef;

            // Salesforce adds a "1." prefix before the base64 string → remove it
            if (base64Context.startsWith("1.")) {
                base64Context = base64Context.substring(2);
            }

            // Decode base64 → JSON → extract recordId
            const context = JSON.parse(window.atob(base64Context));
            recordId = context?.attributes?.recordId || null;
        } catch (e) {
            console.error("Error decoding inContextOfRef:", e);
        }
    }

    return recordId;
}
