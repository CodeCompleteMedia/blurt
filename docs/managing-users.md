# Managing teacher accounts with SQL

Four jobs, each run in the Supabase dashboard under **SQL Editor**: list everyone who has signed up, confirm an account's email by hand, set a new password for an account, and delete chosen accounts.

Only teachers have accounts. Students never sign up, so none of this touches them directly; deleting a teacher does remove the games they hosted and the answers in them.

The `/admin` page in the app shows the same list and has Suspend and Delete buttons. Use SQL when you need something it doesn't do: confirming an email by hand, setting a password, deleting several accounts at once, or deleting an account the page refuses to.

The editor warns "This query includes destructive operations" for the update and delete statements below. That is expected; choose to run it.

## 1. List everyone who has signed up

```sql
select
  u.email,
  u.created_at::date                          as signed_up,
  u.email_confirmed_at is not null            as confirmed,
  u.last_sign_in_at::date                     as last_sign_in,
  coalesce(u.banned_until > now(), false)     as suspended,
  public.plan_of(u.id)                        as plan,
  coalesce(t.comp, false)                     as comp,
  t.status                                    as stripe_status,
  t.current_period_end::date                  as paid_until,
  (select count(*) from public.quizzes z
    where z.owner_id = u.id and z.archived_at is null) as quizzes,
  (select count(*) from public.games g
    where g.owner_id = u.id)                  as rooms
from auth.users u
left join public.teacher_plans t on t.user_id = u.id
order by u.created_at desc;
```

Reading the columns:

- **confirmed**: `false` means they signed up but never clicked the link in the email. They cannot sign in until it is `true`.
- **plan**: `teacher` or `free`, as the database currently enforces it.
- **comp**: `true` means the Teacher plan was given by hand, with no subscription.
- **stripe_status**: Stripe's word for the subscription (`active`, `past_due`, `canceled`), or empty if they never started paying.

To see only the accounts still waiting on their email:

```sql
select email, created_at
from auth.users
where email_confirmed_at is null
order by created_at desc;
```

## 2. Confirm an account by hand

Use this when a teacher's confirmation email never arrived, for example because the email limit was reached. It does what clicking the link would have done. Only confirm an address you have reason to believe is theirs.

**Look first:**

```sql
select email, created_at, email_confirmed_at
from auth.users
where email in ('teacher@example.com');
```

**Then confirm:**

```sql
update auth.users
set email_confirmed_at = now()
where email in ('teacher@example.com')
  and email_confirmed_at is null;
```

The teacher can then sign in with the password they chose. Add more addresses inside the brackets, separated by commas, to confirm several at once.

Confirming by hand skips the trip to payment that the email link makes. A teacher who signed up for the paid plan lands on Free and upgrades from **Plan & billing** in the account menu.

## 3. Set a new password for an account

Use this when a teacher is locked out and the reset email is not reaching them. The normal route is **Forgot your password?** on the sign-in page, which emails them a link and never shows you their password; prefer it whenever email is working.

**Look first:**

```sql
select email, last_sign_in_at
from auth.users
where email = 'teacher@example.com';
```

**Then set it.** Replace the address and the password:

```sql
update auth.users
set encrypted_password = crypt('a-temporary-password', gen_salt('bf'))
where email = 'teacher@example.com';
```

The editor should report one row updated. If it reports none, the address did not match; nothing was changed.

Supabase stores passwords hashed, never as text, and `crypt(..., gen_salt('bf'))` produces the same kind of hash that signing up does. If the editor says `function crypt does not exist`, write `extensions.crypt` and `extensions.gen_salt` instead.

Things to know:

- **Use at least 8 characters.** The app's forms require it; SQL will accept anything.
- **Treat it as temporary.** The password you type stays in the SQL editor's history, and you now know it. Give it to the teacher and ask them to change it straight away, from **Change password** in the account menu.
- **Devices already signed in stay signed in.** To sign the account out everywhere as well, for example if someone else may have had the old password, run:

```sql
delete from auth.sessions
where user_id = (select id from auth.users where email = 'teacher@example.com');
```

## 4. Delete selected accounts

This cannot be undone. It removes the account, their quizzes and questions, the games they hosted, every student answer in those games, their paired displays and their plan record.

**Step 1. Look at exactly who will go, and whether Stripe is still charging them:**

```sql
select u.email, u.created_at::date as signed_up, t.status as stripe_status, t.stripe_customer_id
from auth.users u
left join public.teacher_plans t on t.user_id = u.id
where u.email in (
  'first@example.com',
  'second@example.com'
);
```

If `stripe_status` is `active`, `trialing` or `past_due`, cancel that subscription in Stripe **before** deleting. Deleting the account does not stop Stripe, which would go on charging a card for an account that no longer exists. The `/admin` page refuses such a delete for this reason; SQL does not.

**Step 2. Delete.** Put the same addresses in all three places:

```sql
begin;

-- Games they hosted, which take players, answers and secrets with them.
delete from public.games g using auth.users u
where g.owner_id = u.id
  and u.email in ('first@example.com', 'second@example.com');

-- Older games that point at one of their quizzes.
delete from public.games g using public.quizzes z, auth.users u
where g.quiz_id = z.id and z.owner_id = u.id
  and u.email in ('first@example.com', 'second@example.com');

-- The accounts, which take quizzes, questions, displays, plan rows and sessions.
delete from auth.users
where email in ('first@example.com', 'second@example.com');

commit;
```

Games go first because a game points at its quiz without a cascade: while a game exists, the account that owns its quiz cannot be removed.

What this leaves behind:

- **Question images** the teacher uploaded stay in storage. SQL cannot remove stored files; delete them under **Storage → question-images**, in the folder named with the teacher's user id.
- **The Stripe customer** stays in Stripe, with its payment history.

A deleted address can sign up again as a new account.

## Related: giving someone the Teacher plan

Not a deletion, but it is the other thing done by SQL. This gives the plan with no subscription, and the Stripe webhook never undoes it:

```sql
insert into public.teacher_plans (user_id, comp)
select id, true from auth.users where email = 'teacher@example.com'
on conflict (user_id) do update set comp = true;
```

To take it back, set `comp = false` for that user in the same way.
