# Brief: a real mailbox for hello@blurt.it.com, on Zoho Mail

You are helping me, Matthew, set up a mailbox at `hello@blurt.it.com` using Zoho Mail. You will work in my browser across two sites: Zoho, and wherever the DNS for `blurt.it.com` is managed. You cannot see my code, so this brief is everything you know about the project.

## The situation

Blurt is a classroom quiz app at `https://www.blurt.it.com`. Its sign-up and password-reset emails are already sent through Brevo, from `Blurt <hello@blurt.it.com>`. That is working and tested.

What is missing is anywhere for mail *to* that address to arrive. Today a teacher who replies to a sign-up email gets a bounce. I want a real inbox at `hello@blurt.it.com` that I can read and reply from, and I plan to publish the address on the site as the contact for questions.

Brevo keeps doing the sending for the app. Zoho only receives mail for the address and lets me reply by hand.

## What done looks like

1. Zoho shows `blurt.it.com` as verified, with the mailbox `hello@blurt.it.com`.
2. Mail sent to `hello@blurt.it.com` from outside arrives in the Zoho inbox.
3. A reply sent from Zoho arrives at my personal address and passes SPF and DKIM.
4. Blurt's own emails through Brevo still arrive exactly as before.

## Ask me before you start

- **Where is the DNS for `blurt.it.com` managed?** It is the same place the Brevo records were added. If I don't say, ask.
- **Which Zoho plan?** I expect the cheapest paid plan with one user (I believe it is called Mail Lite, about $1 a month billed yearly). Show me the plans and prices you see and let me choose. Do not pick for me.
- **Which data centre region**, if Zoho asks. I expect United States.

## Rules

- **Stop and hand over to me** for any login, password, two-factor code, phone verification or captcha. I will choose the mailbox password myself. Do not invent, suggest or type one.
- **I enter payment details myself.** When Zoho reaches a payment page, stop and tell me. Do not type card details, and do not accept any add-on or a larger plan than the one I chose.
- **Never show a secret in the chat.** That covers passwords and any app-specific password Zoho generates.
- **In DNS, existing records are not yours to change, with one exception below.** The domain already has records that make Brevo work: a Brevo verification TXT record, Brevo DKIM records and a DMARC record. Do not edit or delete any of them. Do not add a second DMARC record; one already exists and a domain must have only one.
- **The one exception is SPF,** and only with my approval. See Part 2, step 4.
- **If a page looks different from this brief, trust the page.** The record names and values below are from memory and may have changed. Tell me what differed.
- **Change only what this brief names.** Nothing in Supabase, Brevo, Vercel or Stripe needs touching for this.

## Part 1: Zoho account and domain

1. Go to `https://www.zoho.com/mail/`. If I have no Zoho account, tell me and I will create it myself; then continue.
2. Start the setup for a business email with a domain I already own, and enter `blurt.it.com`. Do not buy a domain through Zoho.
3. When it asks for the first user, the address is `hello@blurt.it.com`. This first user is also the administrator. Hand over to me for the password.
4. Zoho will ask me to prove I own the domain, usually with a TXT record that starts `zoho-verification=`. Write down the record type, name and value exactly as shown.

## Part 2: DNS

1. Open the DNS settings for `blurt.it.com`.
2. **Before adding anything, list every existing record and show me.** Tell me specifically:
   - Whether any **MX** record exists. If one does, stop. Something else is already set to receive mail for this domain and I need to decide what happens to it.
   - Whether a TXT record starting `v=spf1` exists, and its full value.
   - The DMARC record (a TXT record at `_dmarc`), so we both know it is there.
3. Add the verification TXT record from Part 1 and have Zoho verify the domain. DNS can take from a minute to an hour. If it has not verified after a few tries, tell me and wait; do not keep retrying indefinitely.
4. **SPF.** Zoho will ask for a record like `v=spf1 include:zohomail.com ~all`. Use the exact value Zoho shows.
   - If the domain has **no** SPF record, add Zoho's as shown.
   - If the domain **already has** an SPF record, do not add a second one. A domain may have only one, and two will send mail to spam. Instead, show me the existing value and a single merged value that keeps everything already in it and adds Zoho's `include:`. For example, an existing `v=spf1 include:spf.brevo.com ~all` would become `v=spf1 include:spf.brevo.com include:zohomail.com ~all`. Wait for my go-ahead before editing.
5. **MX.** Add the MX records Zoho lists, with the priorities it gives. I expect three, along the lines of `mx.zoho.com` (10), `mx2.zoho.com` (20) and `mx3.zoho.com` (50). The host or name is the domain itself, which many providers write as `@`.
6. **DKIM.** In Zoho's admin console, under the domain's email authentication settings, create a DKIM key for `blurt.it.com`. Add the TXT record it gives you, then go back to Zoho and verify it. Its name will contain `._domainkey`. It sits alongside Brevo's DKIM records, which have different names; leave those as they are.
7. Watch for the DNS provider adding the domain to names automatically. A name Zoho shows as `zmail._domainkey.blurt.it.com` may need entering as just `zmail._domainkey`.
8. Do not add a DMARC record, even if Zoho suggests one. Tell me what Zoho suggested and what the existing record says, and I will decide whether to change it.

## Part 3: Prove it works

1. **Receiving.** Ask me to send an email to `hello@blurt.it.com` from my personal address. Confirm it arrives in the Zoho inbox. If it has not arrived after ten minutes, check that the MX records are saved exactly as Zoho listed them.
2. **Replying.** From the Zoho inbox, reply to that email. Ask me to confirm the reply arrived, that it shows as from `hello@blurt.it.com`, and that it did not land in spam. If I use Gmail, ask me to open "Show original" on the reply and tell you whether SPF and DKIM both say PASS.
3. **Brevo still works.** Open `https://www.blurt.it.com/host`, click **Forgot your password?**, enter `matthew+blurt@quiqlabs.com` and submit. This is my own test account; do not use any other address. Ask me to confirm that email arrived as before and is not in spam. Do not click the link in it.

If step 3 fails after working before, the SPF record is the first thing to check: it should be one record containing both senders.

## When you finish

Give me a short report:

- What is now set up, and anything you could not complete.
- Every DNS record you added or changed (type, name, value), with the old value for anything changed. These are not secret.
- The Zoho plan I am on and what it costs.
- Anything that looked different from this brief.
- What I still need to do myself. I expect that to include turning on two-factor sign-in for the Zoho account, and adding the mailbox to the Mail app on my Mac if I want it there.
