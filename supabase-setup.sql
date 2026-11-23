-- =====================================================================
-- MockPrep: Supabase setup. Paste this whole file into Supabase > SQL Editor > Run.
-- Safe to run once on a fresh project.
-- =====================================================================

-- ---------- 1. profiles ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  plan_expiry timestamptz,
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles: read own" on public.profiles;
create policy "profiles: read own" on public.profiles
  for select to authenticated using (auth.uid() = id);

-- No INSERT / UPDATE / DELETE policies exist, and the privileges are revoked too,
-- so a user can NEVER change plan_expiry from the browser. Only you (SQL Editor / service role) can.
revoke insert, update, delete on public.profiles from anon, authenticated;

-- Auto-create a profile row for every new signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill users who signed up before this script ran
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- Helper used by the policies below: does the logged-in user have an active pass?
create or replace function public.has_active_plan()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.plan_expiry is not null and p.plan_expiry > now()
  );
$$;

-- ---------- 2. tests (metadata only, public) ----------
create table if not exists public.tests (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  category         text not null,
  duration_minutes int  not null,
  total_questions  int  not null,
  is_free          boolean not null default false,
  sort_order       int  not null default 0
);

alter table public.tests enable row level security;

drop policy if exists "tests: anyone can read metadata" on public.tests;
create policy "tests: anyone can read metadata" on public.tests
  for select to anon, authenticated using (true);

revoke insert, update, delete on public.tests from anon, authenticated;

-- ---------- 3. test_questions (protected) ----------
create table if not exists public.test_questions (
  id        uuid primary key default gen_random_uuid(),
  test_id   uuid not null unique references public.tests (id) on delete cascade,
  questions jsonb not null  -- [{question, options:[4], correctIndex, explanation}]
);

alter table public.test_questions enable row level security;

drop policy if exists "questions: free test or active pass" on public.test_questions;
create policy "questions: free test or active pass" on public.test_questions
  for select to authenticated
  using (
    exists (select 1 from public.tests t where t.id = test_id and t.is_free)
    or public.has_active_plan()
  );

revoke insert, update, delete on public.test_questions from anon, authenticated;

-- ---------- 4. test_attempts ----------
create table if not exists public.test_attempts (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  test_id            uuid not null references public.tests (id) on delete cascade,
  score              int  not null,
  total              int  not null,
  time_taken_seconds int,
  submitted_at       timestamptz not null default now()
);

create index if not exists test_attempts_user_idx on public.test_attempts (user_id, submitted_at desc);

alter table public.test_attempts enable row level security;

drop policy if exists "attempts: read own" on public.test_attempts;
create policy "attempts: read own" on public.test_attempts
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "attempts: insert own" on public.test_attempts;
create policy "attempts: insert own" on public.test_attempts
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and (exists (select 1 from public.tests t where t.id = test_id and t.is_free) or public.has_active_plan())
  );

revoke update, delete on public.test_attempts from anon, authenticated;

-- ---------- 5. seed: 12 sample tests (10 free, 2 paid), 5 questions each ----------
insert into public.tests (id, title, category, duration_minutes, total_questions, is_free, sort_order) values
  ('4d6f9f00-0f71-5f88-b944-4d57838bbe74', 'SSC Mock Test 1', 'SSC', 10, 5, true, 1),
  ('6f218f08-1a06-587a-b28b-565599e9770a', 'Banking Mock Test 2', 'Banking', 10, 5, true, 2),
  ('9ea467fe-299e-5fe8-98a3-da1f91f24d42', 'Railways Mock Test 3', 'Railways', 10, 5, true, 3),
  ('fc571573-4693-543e-a31e-12c517f32534', 'General Mock Test 4', 'General', 10, 5, true, 4),
  ('ab26853d-904d-52ad-8d41-e9c4570df6ef', 'SSC Mock Test 5', 'SSC', 10, 5, true, 5),
  ('17b6eab7-5f16-517a-b191-5aaf7c8df9de', 'Banking Mock Test 6', 'Banking', 10, 5, true, 6),
  ('88b047fe-9a64-537c-b0d4-77608efd1f89', 'Railways Mock Test 7', 'Railways', 10, 5, true, 7),
  ('39e904a3-a745-5797-a165-5fe4af07e835', 'General Mock Test 8', 'General', 10, 5, true, 8),
  ('ba9d97fc-fd1d-5d61-be0d-c7e0f218ea27', 'SSC Mock Test 9', 'SSC', 10, 5, true, 9),
  ('ab98034f-d4e8-570b-b234-488dda856a1d', 'Banking Mock Test 10', 'Banking', 10, 5, true, 10),
  ('ee5c1dc2-3fdd-58aa-b14d-97d20859eba1', 'Railways Mock Test 11 (Pro)', 'Railways', 10, 5, false, 11),
  ('8c287272-ab94-56eb-bef1-7cdfce165e50', 'General Mock Test 12 (Pro)', 'General', 10, 5, false, 12)
on conflict (id) do nothing;

insert into public.test_questions (test_id, questions) values
  ('4d6f9f00-0f71-5f88-b944-4d57838bbe74', $q$[{"question": "What is 15% of 240?", "options": ["32", "36", "40", "24"], "correctIndex": 1, "explanation": "15/100 x 240 = 36."}, {"question": "A 120 m long train running at 54 km/h crosses a pole in how many seconds?", "options": ["6", "8", "10", "12"], "correctIndex": 1, "explanation": "54 km/h = 15 m/s. Time = 120 / 15 = 8 s."}, {"question": "What is the simple interest on Rs 5000 at 8% per annum for 3 years?", "options": ["Rs 1000", "Rs 1200", "Rs 1400", "Rs 1500"], "correctIndex": 1, "explanation": "SI = 5000 x 8 x 3 / 100 = 1200."}, {"question": "If A:B = 2:3 and B:C = 4:5, then A:B:C = ?", "options": ["8:12:15", "2:4:5", "6:12:15", "8:10:15"], "correctIndex": 0, "explanation": "Make B equal: A:B = 8:12 and B:C = 12:15."}, {"question": "What is the average of the first 10 natural numbers?", "options": ["5", "5.5", "6", "6.5"], "correctIndex": 1, "explanation": "Sum = 55, so average = 5.5."}]$q$::jsonb),
  ('6f218f08-1a06-587a-b28b-565599e9770a', $q$[{"question": "Find the next number: 2, 6, 12, 20, 30, ?", "options": ["40", "42", "44", "46"], "correctIndex": 1, "explanation": "Differences are 4, 6, 8, 10, 12, so next = 42."}, {"question": "Choose the odd one out.", "options": ["Apple", "Mango", "Potato", "Banana"], "correctIndex": 2, "explanation": "Potato is a vegetable; the others are fruits."}, {"question": "If A=1, B=2, C=3 and so on, what is the sum of the letters in BAD?", "options": ["5", "6", "7", "8"], "correctIndex": 2, "explanation": "B + A + D = 2 + 1 + 4 = 7."}, {"question": "A person walks 5 km north and then 5 km east. How far is he from the start?", "options": ["5 km", "About 7.07 km", "10 km", "2.5 km"], "correctIndex": 1, "explanation": "Distance = 5 x sqrt(2), about 7.07 km."}, {"question": "Pointing to a man, a woman said, 'He is the son of my mother's only son.' How is the man related to the woman?", "options": ["Brother", "Nephew", "Uncle", "Son"], "correctIndex": 1, "explanation": "Her mother's only son is her brother, so his son is her nephew."}]$q$::jsonb),
  ('9ea467fe-299e-5fe8-98a3-da1f91f24d42', $q$[{"question": "Choose the synonym of 'Abundant'.", "options": ["Scarce", "Plentiful", "Rare", "Limited"], "correctIndex": 1, "explanation": "Abundant means existing in large quantities, the same as plentiful."}, {"question": "Choose the antonym of 'Ancient'.", "options": ["Old", "Modern", "Historic", "Antique"], "correctIndex": 1, "explanation": "Modern is the opposite of ancient."}, {"question": "Fill in the blank: She has been working here ___ 2019.", "options": ["for", "since", "from", "by"], "correctIndex": 1, "explanation": "'Since' is used with a point in time."}, {"question": "Who is known as the Father of the Indian Constitution?", "options": ["Mahatma Gandhi", "Jawaharlal Nehru", "Dr. B. R. Ambedkar", "Sardar Patel"], "correctIndex": 2, "explanation": "Dr. B. R. Ambedkar chaired the Drafting Committee."}, {"question": "What is the capital of Australia?", "options": ["Sydney", "Melbourne", "Canberra", "Perth"], "correctIndex": 2, "explanation": "Canberra is the capital of Australia."}]$q$::jsonb),
  ('fc571573-4693-543e-a31e-12c517f32534', $q$[{"question": "What is 15% of 240?", "options": ["32", "36", "40", "24"], "correctIndex": 1, "explanation": "15/100 x 240 = 36."}, {"question": "A 120 m long train running at 54 km/h crosses a pole in how many seconds?", "options": ["6", "8", "10", "12"], "correctIndex": 1, "explanation": "54 km/h = 15 m/s. Time = 120 / 15 = 8 s."}, {"question": "What is the simple interest on Rs 5000 at 8% per annum for 3 years?", "options": ["Rs 1000", "Rs 1200", "Rs 1400", "Rs 1500"], "correctIndex": 1, "explanation": "SI = 5000 x 8 x 3 / 100 = 1200."}, {"question": "If A:B = 2:3 and B:C = 4:5, then A:B:C = ?", "options": ["8:12:15", "2:4:5", "6:12:15", "8:10:15"], "correctIndex": 0, "explanation": "Make B equal: A:B = 8:12 and B:C = 12:15."}, {"question": "What is the average of the first 10 natural numbers?", "options": ["5", "5.5", "6", "6.5"], "correctIndex": 1, "explanation": "Sum = 55, so average = 5.5."}]$q$::jsonb),
  ('ab26853d-904d-52ad-8d41-e9c4570df6ef', $q$[{"question": "Find the next number: 2, 6, 12, 20, 30, ?", "options": ["40", "42", "44", "46"], "correctIndex": 1, "explanation": "Differences are 4, 6, 8, 10, 12, so next = 42."}, {"question": "Choose the odd one out.", "options": ["Apple", "Mango", "Potato", "Banana"], "correctIndex": 2, "explanation": "Potato is a vegetable; the others are fruits."}, {"question": "If A=1, B=2, C=3 and so on, what is the sum of the letters in BAD?", "options": ["5", "6", "7", "8"], "correctIndex": 2, "explanation": "B + A + D = 2 + 1 + 4 = 7."}, {"question": "A person walks 5 km north and then 5 km east. How far is he from the start?", "options": ["5 km", "About 7.07 km", "10 km", "2.5 km"], "correctIndex": 1, "explanation": "Distance = 5 x sqrt(2), about 7.07 km."}, {"question": "Pointing to a man, a woman said, 'He is the son of my mother's only son.' How is the man related to the woman?", "options": ["Brother", "Nephew", "Uncle", "Son"], "correctIndex": 1, "explanation": "Her mother's only son is her brother, so his son is her nephew."}]$q$::jsonb),
  ('17b6eab7-5f16-517a-b191-5aaf7c8df9de', $q$[{"question": "Choose the synonym of 'Abundant'.", "options": ["Scarce", "Plentiful", "Rare", "Limited"], "correctIndex": 1, "explanation": "Abundant means existing in large quantities, the same as plentiful."}, {"question": "Choose the antonym of 'Ancient'.", "options": ["Old", "Modern", "Historic", "Antique"], "correctIndex": 1, "explanation": "Modern is the opposite of ancient."}, {"question": "Fill in the blank: She has been working here ___ 2019.", "options": ["for", "since", "from", "by"], "correctIndex": 1, "explanation": "'Since' is used with a point in time."}, {"question": "Who is known as the Father of the Indian Constitution?", "options": ["Mahatma Gandhi", "Jawaharlal Nehru", "Dr. B. R. Ambedkar", "Sardar Patel"], "correctIndex": 2, "explanation": "Dr. B. R. Ambedkar chaired the Drafting Committee."}, {"question": "What is the capital of Australia?", "options": ["Sydney", "Melbourne", "Canberra", "Perth"], "correctIndex": 2, "explanation": "Canberra is the capital of Australia."}]$q$::jsonb),
  ('88b047fe-9a64-537c-b0d4-77608efd1f89', $q$[{"question": "What is 15% of 240?", "options": ["32", "36", "40", "24"], "correctIndex": 1, "explanation": "15/100 x 240 = 36."}, {"question": "A 120 m long train running at 54 km/h crosses a pole in how many seconds?", "options": ["6", "8", "10", "12"], "correctIndex": 1, "explanation": "54 km/h = 15 m/s. Time = 120 / 15 = 8 s."}, {"question": "What is the simple interest on Rs 5000 at 8% per annum for 3 years?", "options": ["Rs 1000", "Rs 1200", "Rs 1400", "Rs 1500"], "correctIndex": 1, "explanation": "SI = 5000 x 8 x 3 / 100 = 1200."}, {"question": "If A:B = 2:3 and B:C = 4:5, then A:B:C = ?", "options": ["8:12:15", "2:4:5", "6:12:15", "8:10:15"], "correctIndex": 0, "explanation": "Make B equal: A:B = 8:12 and B:C = 12:15."}, {"question": "What is the average of the first 10 natural numbers?", "options": ["5", "5.5", "6", "6.5"], "correctIndex": 1, "explanation": "Sum = 55, so average = 5.5."}]$q$::jsonb),
  ('39e904a3-a745-5797-a165-5fe4af07e835', $q$[{"question": "Find the next number: 2, 6, 12, 20, 30, ?", "options": ["40", "42", "44", "46"], "correctIndex": 1, "explanation": "Differences are 4, 6, 8, 10, 12, so next = 42."}, {"question": "Choose the odd one out.", "options": ["Apple", "Mango", "Potato", "Banana"], "correctIndex": 2, "explanation": "Potato is a vegetable; the others are fruits."}, {"question": "If A=1, B=2, C=3 and so on, what is the sum of the letters in BAD?", "options": ["5", "6", "7", "8"], "correctIndex": 2, "explanation": "B + A + D = 2 + 1 + 4 = 7."}, {"question": "A person walks 5 km north and then 5 km east. How far is he from the start?", "options": ["5 km", "About 7.07 km", "10 km", "2.5 km"], "correctIndex": 1, "explanation": "Distance = 5 x sqrt(2), about 7.07 km."}, {"question": "Pointing to a man, a woman said, 'He is the son of my mother's only son.' How is the man related to the woman?", "options": ["Brother", "Nephew", "Uncle", "Son"], "correctIndex": 1, "explanation": "Her mother's only son is her brother, so his son is her nephew."}]$q$::jsonb),
  ('ba9d97fc-fd1d-5d61-be0d-c7e0f218ea27', $q$[{"question": "Choose the synonym of 'Abundant'.", "options": ["Scarce", "Plentiful", "Rare", "Limited"], "correctIndex": 1, "explanation": "Abundant means existing in large quantities, the same as plentiful."}, {"question": "Choose the antonym of 'Ancient'.", "options": ["Old", "Modern", "Historic", "Antique"], "correctIndex": 1, "explanation": "Modern is the opposite of ancient."}, {"question": "Fill in the blank: She has been working here ___ 2019.", "options": ["for", "since", "from", "by"], "correctIndex": 1, "explanation": "'Since' is used with a point in time."}, {"question": "Who is known as the Father of the Indian Constitution?", "options": ["Mahatma Gandhi", "Jawaharlal Nehru", "Dr. B. R. Ambedkar", "Sardar Patel"], "correctIndex": 2, "explanation": "Dr. B. R. Ambedkar chaired the Drafting Committee."}, {"question": "What is the capital of Australia?", "options": ["Sydney", "Melbourne", "Canberra", "Perth"], "correctIndex": 2, "explanation": "Canberra is the capital of Australia."}]$q$::jsonb),
  ('ab98034f-d4e8-570b-b234-488dda856a1d', $q$[{"question": "What is 15% of 240?", "options": ["32", "36", "40", "24"], "correctIndex": 1, "explanation": "15/100 x 240 = 36."}, {"question": "A 120 m long train running at 54 km/h crosses a pole in how many seconds?", "options": ["6", "8", "10", "12"], "correctIndex": 1, "explanation": "54 km/h = 15 m/s. Time = 120 / 15 = 8 s."}, {"question": "What is the simple interest on Rs 5000 at 8% per annum for 3 years?", "options": ["Rs 1000", "Rs 1200", "Rs 1400", "Rs 1500"], "correctIndex": 1, "explanation": "SI = 5000 x 8 x 3 / 100 = 1200."}, {"question": "If A:B = 2:3 and B:C = 4:5, then A:B:C = ?", "options": ["8:12:15", "2:4:5", "6:12:15", "8:10:15"], "correctIndex": 0, "explanation": "Make B equal: A:B = 8:12 and B:C = 12:15."}, {"question": "What is the average of the first 10 natural numbers?", "options": ["5", "5.5", "6", "6.5"], "correctIndex": 1, "explanation": "Sum = 55, so average = 5.5."}]$q$::jsonb),
  ('ee5c1dc2-3fdd-58aa-b14d-97d20859eba1', $q$[{"question": "Find the next number: 2, 6, 12, 20, 30, ?", "options": ["40", "42", "44", "46"], "correctIndex": 1, "explanation": "Differences are 4, 6, 8, 10, 12, so next = 42."}, {"question": "Choose the odd one out.", "options": ["Apple", "Mango", "Potato", "Banana"], "correctIndex": 2, "explanation": "Potato is a vegetable; the others are fruits."}, {"question": "If A=1, B=2, C=3 and so on, what is the sum of the letters in BAD?", "options": ["5", "6", "7", "8"], "correctIndex": 2, "explanation": "B + A + D = 2 + 1 + 4 = 7."}, {"question": "A person walks 5 km north and then 5 km east. How far is he from the start?", "options": ["5 km", "About 7.07 km", "10 km", "2.5 km"], "correctIndex": 1, "explanation": "Distance = 5 x sqrt(2), about 7.07 km."}, {"question": "Pointing to a man, a woman said, 'He is the son of my mother's only son.' How is the man related to the woman?", "options": ["Brother", "Nephew", "Uncle", "Son"], "correctIndex": 1, "explanation": "Her mother's only son is her brother, so his son is her nephew."}]$q$::jsonb),
  ('8c287272-ab94-56eb-bef1-7cdfce165e50', $q$[{"question": "Choose the synonym of 'Abundant'.", "options": ["Scarce", "Plentiful", "Rare", "Limited"], "correctIndex": 1, "explanation": "Abundant means existing in large quantities, the same as plentiful."}, {"question": "Choose the antonym of 'Ancient'.", "options": ["Old", "Modern", "Historic", "Antique"], "correctIndex": 1, "explanation": "Modern is the opposite of ancient."}, {"question": "Fill in the blank: She has been working here ___ 2019.", "options": ["for", "since", "from", "by"], "correctIndex": 1, "explanation": "'Since' is used with a point in time."}, {"question": "Who is known as the Father of the Indian Constitution?", "options": ["Mahatma Gandhi", "Jawaharlal Nehru", "Dr. B. R. Ambedkar", "Sardar Patel"], "correctIndex": 2, "explanation": "Dr. B. R. Ambedkar chaired the Drafting Committee."}, {"question": "What is the capital of Australia?", "options": ["Sydney", "Melbourne", "Canberra", "Perth"], "correctIndex": 2, "explanation": "Canberra is the capital of Australia."}]$q$::jsonb)
on conflict (test_id) do nothing;

-- =====================================================================
-- ADMIN: activate a user after you verify their Rs 29 UPI payment
-- (run in SQL Editor; replace the email)
--
--   update public.profiles
--   set plan_expiry = now() + interval '30 days'
--   where email = 'student@example.com';
--
-- Renewing while the old pass is still active? Add the days on top instead:
--
--   update public.profiles
--   set plan_expiry = greatest(coalesce(plan_expiry, now()), now()) + interval '30 days'
--   where email = 'student@example.com';
-- =====================================================================
