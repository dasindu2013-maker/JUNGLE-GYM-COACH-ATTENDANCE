/**
 * Jungle Gym membership commission integration for Google Apps Script.
 *
 * Commission rules:
 * - New memberships and renewals: 10%
 * - Receipt number beginning with "free" (case-insensitive): 0%
 * - Staff "Alpha" is mapped to Harshana in Coach Payroll.
 *
 * SETUP
 * 1. Run the updated supabase-payroll-module.sql in the attendance Supabase project.
 * 2. Add Apps Script property ATTENDANCE_SYNC_SECRET with the same private value
 *    used in the Supabase integration_secrets setup statement.
 * 3. Apply the two edits below to Code.gs and redeploy the Apps Script web app.
 */


/* EDIT 1 — replace the existing duplicate receipt check with this.
 * This permits multiple complimentary registrations while retaining duplicate
 * protection for every normal receipt number.
 */
if (
  !normalizeReceipt_(receiptNumber).startsWith('free') &&
  receiptExists_(sheet, headers, receiptNumber)
) {
  throw new Error(
    'That receipt number has already been registered. Check the Sheet before submitting again.'
  );
}


/* EDIT 2 — insert this block after the members.forEach(...) external-sync loop
 * and immediately before the final "return {ok: true, ...}" statement.
 * Only one commission is created per package, using the primary paid amount.
 */
try {
  syncAttendanceCommission_({
    source_key:
      'google-sheet:' +
      REGISTRATION_CONFIG.spreadsheetId +
      ':' +
      REGISTRATION_CONFIG.sheetName +
      ':' +
      firstRow +
      ':commission',
    receipt_number: receiptNumber,
    registration_type:
      type === 'renewal' ? 'Membership Renewal' : 'New Member',
    payment_date: paymentDate,
    staff_name: staffName,
    member_name: members[0].fullName,
    nic_number: members[0].identityNumber,
    paid_amount: paidAmount
  });
} catch (error) {
  failures += 1;
  console.error(
    'Registration saved; attendance payroll commission sync is pending.'
  );
}


/* EDIT 3 — add this helper function near syncRegistrationRow_ in Code.gs. */
function syncAttendanceCommission_(row) {
  const secret = PropertiesService
    .getScriptProperties()
    .getProperty('ATTENDANCE_SYNC_SECRET');

  if (!secret) {
    throw new Error(
      'ATTENDANCE_SYNC_SECRET script property is not configured'
    );
  }

  const response = UrlFetchApp.fetch(
    'https://ucdsahpfllanlqxfcjjk.supabase.co/rest/v1/rpc/' +
      'sync_membership_commission',
    {
      method: 'post',
      contentType: 'application/json',
      headers: {
        apikey: 'sb_publishable_vcXp8NtRACdZb6OfDefdtg_NBXC6vLZ',
        Authorization:
          'Bearer sb_publishable_vcXp8NtRACdZb6OfDefdtg_NBXC6vLZ'
      },
      payload: JSON.stringify({
        p_secret: secret,
        p_row: row
      }),
      muteHttpExceptions: true
    }
  );

  const status = response.getResponseCode();

  if (status < 200 || status >= 300) {
    // Do not log names, receipt details, or the secret.
    throw new Error('Attendance Supabase HTTP ' + status);
  }
}
