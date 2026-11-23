# MockPrep (Astro + Tailwind + Supabase)

Static site for GitHub Pages. Free tests for every registered user, paid tests unlocked by a 30 day pass
that you activate manually after a UPI payment.

## 1. Supabase
1. Create a project at supabase.com.
2. SQL Editor > paste `supabase-setup.sql` > Run. This creates the tables, the signup trigger, the RLS policies and 12 seed tests.
3. Project Settings > API: copy the **Project URL** and the **anon public** key.
4. Authentication > Providers > Email: for easiest testing turn **Confirm email** off (optional).
5. Authentication > URL Configuration: set **Site URL** to your GitHub Pages URL and add it (and `http://localhost:4321`) to **Redirect URLs**.

## 2. Edit your details
- `src/lib/config.js`: `ADMIN_UPI_ID`, `WHATSAPP_NUMBER`, price and days.
- Replace `public/upi-qr.png` with your own UPI QR image.

## 3. Run locally
    npm install
    cp .env.example .env     # add your Supabase URL and anon key
    npm run dev

## 4. Deploy on GitHub Pages
1. Push this folder to a GitHub repo (branch `main`).
2. Repo > Settings > Secrets and variables > Actions > add `PUBLIC_SUPABASE_URL` and `PUBLIC_SUPABASE_ANON_KEY`.
3. Repo > Settings > Pages > Source: **GitHub Actions**.
4. Every push to `main` builds and deploys. The workflow sets `base` from the repo name automatically.

## Activating a paying user
After you see the Rs 29 payment in your UPI app, run in the Supabase SQL Editor:

    update public.profiles
    set plan_expiry = now() + interval '30 days'
    where email = 'student@example.com';

The site checks `plan_expiry > now()` and re-locks paid tests when it passes.

## Adding tests
Insert a row in `tests`, then a row in `test_questions` with `questions` as a JSON array:
`[{"question":"...","options":["a","b","c","d"],"correctIndex":1,"explanation":"..."}]`
Set `is_free` to true or false. The Table Editor in Supabase works for this too.

## Security notes
- The anon key is public by design. Safety comes from RLS in `supabase-setup.sql`.
- Users cannot update `profiles`, so they cannot give themselves a pass.
- Paid questions are only returned by the database to users with an active pass.
