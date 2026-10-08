# Brief: send Blurt's sign-up email through Brevo

You are helping me, Matthew, set up Brevo as the email sender for my app's sign-up and password-reset emails. You will work in my browser across three sites: Brevo, wherever my domain's DNS is managed, and Supabase. You cannot see my code, so this brief is everything you know about the project.

## The situation

Blurt is a classroom quiz app at `https://www.blurt.it.com`. Teachers sign up with an email and password, and Supabase Auth emails them a confirmation link. Password resets work the same way. Students never get email.

Supabase's built-in email sender only allows about two emails an hour for the whole project. The third teacher to sign up in an hour gets "email rate limit exceeded" and no account. I launch tomorrow, so this has to be fixed first.

The fix is to have Supabase send through Brevo's SMTP service from my own domain, then raise Supabase's email rate limit.

## What done looks like

1. Brevo shows the domain `blurt.it.com` as authenticated.
2. Supabase's custom SMTP is on and uses Brevo, with the sender name `Blurt`.
3. Supabase's email rate limit is raised.
4. A password-reset email, triggered from the live site, arrives from the Blurt address.

## Ask me before you start

- **Which address should email come from?** My default is `hello@blurt.it.com`. Confirm it with me. It must be on `blurt.it.com`.
- **Where is the DNS for `blurt.it.com` managed?** I may not remember. If I don't, check Vercel first (the domain is attached to a Vercel project called `blurt`, under Settings → Domains, which says whether Vercel or another provider holds the DNS).

## Rules

- **Stop and hand over to me** for any login, password, two-factor code, phone verification or captcha. Do not guess or try to recover credentials.
- **Never show a secret in the chat.** The Brevo SMTP key is a password. Copy it straight from Brevo into Supabase's field. Do not paste it into a message, a note or a search box.
- **Spend nothing.** Stay on Brevo's free plan. If any step asks for a card or an upgrade, stop and tell me.
- **Change only what this brief names.** In particular, leave these alone:
  - In Supabase: the Site URL, the Redirect URLs, the database, and API keys.
  - In DNS: every existing record. You are only adding records. If a record Brevo asks for seems to clash with one that already exists (for example an existing SPF or DMARC record), stop and show me both; do not overwrite or delete.
- **If a page looks different from this brief, trust the page.** Menu names and record formats below are from memory and may have changed. Tell me what differed.
- **If Brevo says the account or SMTP sending needs a review or activation** before it can send, stop and tell me exactly what it asks for. Do not open support tickets on my behalf without asking.

## Part 1: Brevo

1. Go to `https://www.brevo.com`. If I have no account, tell me and I will sign up myself; then continue.
2. Add and authenticate the domain `blurt.it.com`. Look under the account menu → **Senders, Domains & Dedicated IPs** → **Domains** → **Add a domain**. If Brevo offers to set the records up automatically by connecting to my DNS provider, do not use that; choose the manual option so we can see each record.
3. Brevo will list DNS records to add. Expect roughly these: a TXT record with a Brevo verification code, one or two DKIM records, and a DMARC TXT record. Write down each record's type, name and value exactly as shown.
4. Add a sender: under **Senders**, add the address we agreed with the name `Blurt`.

## Part 2: DNS

1. Open the DNS settings for `blurt.it.com` at the provider we identified.
2. Before adding anything, list the records that already exist and tell me if any is a TXT record starting `v=spf1` or `v=DMARC1`, or sits at a name Brevo wants to use.
3. Add each record from Brevo exactly as given. Watch for the provider adding the domain to the name automatically: a name Brevo shows as `brevo1._domainkey.blurt.it.com` may need entering as just `brevo1._domainkey`.
4. Go back to Brevo and press the button that verifies the domain. DNS can take from a minute to an hour. If it has not verified after a few tries, tell me which record Brevo says is missing; do not keep retrying indefinitely.

## Part 3: Supabase

The project is at `https://supabase.com/dashboard/project/ijxarffatlsasimchaop`.

1. In Brevo, open **SMTP & API** → **SMTP**. You need the SMTP server, port, login, and an SMTP key. Generate a new SMTP key named `supabase` if none exists. The login is the SMTP login Brevo shows there, which is not my account email. The SMTP key is not the same thing as an API key.
2. In Supabase, go to **Authentication** → **Emails** → **SMTP Settings** and turn on custom SMTP. Fill in:
   - Sender email: the address we agreed
   - Sender name: `Blurt`
   - Host: as Brevo shows (I expect `smtp-relay.brevo.com`)
   - Port: `587`
   - Username: Brevo's SMTP login
   - Password: the SMTP key
   - Leave the minimum interval between emails at its default.
3. Save, and confirm the page shows custom SMTP as enabled.
4. Go to **Authentication** → **Rate Limits**. Find the limit for sending emails and set it to `100` per hour. Brevo's free plan allows about 300 emails a day, so this leaves headroom without letting a runaway loop spend the whole day's allowance in minutes. Save.
5. Go to **Authentication** → **Emails** → **Templates**. Read the "Confirm signup" and "Reset password" templates and show me their subject lines and body text. Do not edit them yet. I want the product name written `Blurt` with a capital B; propose wording changes and wait for my go-ahead. Whatever changes, the link placeholder (it looks like `{{ .ConfirmationURL }}`) must stay exactly as it is.

## Part 4: Prove it works

Use a password reset, because it sends a real email without creating a new account.

1. Open `https://www.blurt.it.com/host`.
2. Click **Forgot your password?**, enter `matthew+blurt@quiqlabs.com`, and submit. This is my own test account. Do not use any other address.
3. Ask me to check that inbox. I will tell you whether the email arrived, who it says it is from, and whether it landed in spam. Do not click the link in the email.
4. In Brevo, open the transactional email logs and confirm the message shows as delivered.

If the site shows an error instead of "If that address has an account, a reset link is on its way", copy the exact message to me. In Supabase, **Logs** → **Auth** will usually show why sending failed.

## When you finish

Give me a short report:

- What is now set up, and anything you could not complete.
- Every DNS record you added (type, name, value). These are not secret.
- The Supabase settings you changed, without the SMTP key.
- Anything that looked different from this brief.
- Anything I still need to do myself.
