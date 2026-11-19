# Manual commission cancellation

This update adds **Cancel Commission** to the Coach Attendance admin Payroll section. It requires a reason, confirms the selected receipt, excludes the commission from payroll and its reports, and keeps a cancellation history. Re-syncing the same source entry cannot restore its commission.

It does not delete a membership, a Google Sheet registration, payment history, or referral rewards. Installing the SQL does not cancel any existing commission.

## Install in this order

1. Open the **Jungle Gym Coach Attendance** Supabase project (not the membership project).
2. Open **SQL Editor → New query**. Paste the complete contents of `supabase-commission-cancellation.sql`, then click **Run**. This requires the existing payroll and commission correction setup, including `public.is_admin()`.
3. After the SQL succeeds, merge this update into the GitHub repository's `main` branch and wait for GitHub Pages deployment. If installing manually, replace the entire repository `index.html` with the included file.
4. Open the Coach Attendance app and sign in as an administrator. Refresh the page, then open **Payroll** and choose the payment month.
5. Under **Correct or Cancel Membership Commissions**, find the exact receipt, enter a reason and click **Cancel Commission**. Check the member, receipt, coach and amount in the confirmation before proceeding.
6. Confirm the coach's payroll total decreases and the entry appears under **Cancelled commissions — selected payment month**. Refresh again to verify persistence.

For the duplicate registration previously removed from Sheet row 271, review **November 2026**, **Kalindu**, receipt **10117**, coach **Chaminda**, expected commission **LKR 2,600**. Keep receipt **10129**. No commission has been cancelled by this code update itself.

## Validation

Run `node tests/commission-cancellation.test.cjs` to check browser-handler authorization, required reason, exact receipt/source snapshot, double-click protection, payroll exclusion, failure handling and cancellation metadata.

The JavaScript has been syntax checked and the mocked handler tests pass. The SQL must still be run and verified in your Supabase project; it has not been executed against your live database.
