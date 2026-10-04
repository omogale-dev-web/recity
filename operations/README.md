# ReCity Operations

Mobile-first municipal and collector companion app for ReCity. This initial build uses local demo data only; it does not yet read or write Supabase.

## Screens included

- Collector availability and nearby-report alert
- Accept/reject flow with points updates
- Active-task and proof-submission flow
- Municipal live-report and assignment view

## Next integration step

Replace the demo data in `js/app.js` with secure server/API calls that read ReCity's `complaints` table and write collector, dispatch, assignment, proof, and points records.

Deploy this `operations/` directory as a separate Vercel project when ready.
