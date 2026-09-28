# RECITY

RECITY is a vanilla JavaScript PWA for citizen waste reporting, reuse guidance, and municipal follow-up.

## Live citizen flow

1. A visitor creates an anonymous RECITY identity in Supabase.
2. **Take photo** opens the device camera; **Upload from gallery** uses the image picker.
3. The browser compresses the selected image to 2.5 MB or less.
4. The authenticated image is sent to Vercel's protected API, which calls Groq Vision without exposing the Groq key.
5. A submitted report uploads its photo to a private Supabase Storage bucket and creates the complaint, detected items, points, and eco event in one database transaction.

The municipal dashboard and DIY guide generator still use prototype data. Do not use those two areas as operational municipal tooling yet.

## Supabase setup

The user has already run migrations 1 and 2. Run the remaining file next in the Supabase SQL Editor:

`supabase/migrations/20260928_000003_complaint_photos_and_submission.sql`

It creates the private `complaint-photos` bucket, its access policies, and the secure `submit_complaint` database function.

## Vercel deployment

1. Put this folder in a GitHub repository and import it in Vercel. The framework preset is **Other**; no build command is needed.
2. In Vercel → Project → Settings → Environment Variables, add:

   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
   - `GROQ_API_KEY` (server-only; never put this in a frontend file)
   - `GROQ_VISION_MODEL` = `qwen/qwen3.8-27b` (optional)

3. Deploy. Vercel serves the static PWA and `/api/analyze-waste` together.
4. Test on a phone over the deployed HTTPS URL. The camera prompt appears only after the user taps **Take photo**.

The public Supabase URL and publishable key belong in `js/config.js`. They are designed to be public. The Groq key must stay in Vercel only.

## Local preview

Use any static server for the interface. AI analysis requires Vercel's local development environment (or a deployed Vercel URL) because it uses the server endpoint.
