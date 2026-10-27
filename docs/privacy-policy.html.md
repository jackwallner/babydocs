# Baby Docs: Privacy Policy

> Privacy policy for the Baby Docs newborn paperwork app by Jack Wallner.

Web page: https://jackwallner.com/ios/babydocs/privacy-policy.html

## Baby Docs Privacy Policy

Last updated: August 23, 2026

## Overview

Baby Docs is an iPhone app for keeping track of the paperwork that follows
a birth: the Social Security card, the birth certificate, health plan
enrollment, parental leave and so on. It tells you what applies to your
household, when each window closes, and which official office issues each
thing.

**Baby Docs has no account and no household-data backend.**
There is nothing to sign in to, and we hold no copy of your child, your
household answers, your plan, your notes or your documents. Almost
everything below is a description of what stays on your own iPhone.

There is one exception, and it is worth stating at the top rather than
burying it:
**the app checks purchase status with Apple and RevenueCat**.
RevenueCat can receive an anonymous app identifier and purchase-status
information even before a purchase, because the app needs to know whether
Plus is already active. That is the only thing about you that ever reaches
a server of ours, it contains nothing about your family, and it is
described in full under
Purchases and Baby Docs Plus.

## The one thing we do not collect

**Baby Docs never asks for, stores or transmits a Social Security
number**, for your child or for you. The app tracks whether the number has been
requested and whether the card has arrived. It has no field for the number
itself, and neither the one-page summary nor the employer packet ever
prints one. Free-text fields reject common Social Security-number
patterns, so a number entered in a note, receipt or household field is not
saved.

One clarification, because it matters. If you photograph a Social Security
card into the document vault, that photograph obviously contains the
number. It is stored as an image file on your iPhone only, held to iOS's
strictest file protection, excluded from every backup, and no share sheet,
export or summary in the app can reach it. We never receive it, because
there is nowhere for it to go.

## What is stored on your iPhone

- Your child's first name, date of birth, the state and county the birth
  was registered in, and whether the Social Security card and birth
  certificate have arrived.
- Your household answers: the state you live in, how the family is
  covered, whether the parents are married, and which optional things
  (passport, 529, parental leave) you want on the list.
- The generated plan: each task, its deadline, which documents you have
  gathered, who it is assigned to, and any confirmation or tracking
  numbers you choose to record.
- Any notes you write.
- Photographs you choose to add to the document vault, and nothing about
  them beyond what you named them.
- If you leave setup unfinished, the answers needed to resume it are kept
  in the app's local preferences for up to seven days, then removed.

The local database is encrypted at rest by iOS until you first enter
your passcode after the phone boots. Vault photographs are held to a stricter setting
again: unreadable whenever the phone is locked, and marked so they are
never included in an iCloud or computer backup. That is a real trade-off
and it is worth stating plainly: a new iPhone will not restore
them, so keep the original documents where you always kept them.

## What leaves your iPhone, and when

Only what you deliberately send, and only to whoever you send it to, plus
purchase-status requests to Apple and RevenueCat, and one Apple
system-service request if you tap the location helper. There is no
household-data upload, no account and no Baby Docs server copy.

- **Sending the plan to the other parent.** This creates a
  link containing the answers that build a plan (your child's first
  name, their date of birth, the state and county the birth was registered
  in, the state you live in, and your household answers such as how you
  are covered), so their phone can rebuild the same plan. The
  answers travel in the part of a web address that browsers never send to
  a server, so even though the link opens a page on our site, that page
  receives nothing. If you entered them, the link also carries the
  job-based plan name and benefits contact because the other phone needs
  those answers to rebuild the same plan. It carries no completed tasks,
  no notes, no confirmation numbers and no photographs. Anyone the link is
  forwarded to can read what is in it, so send it the way you would send a
  page of a form.
- **The one-page summary and the employer packet.** Plain
  text you generate and share yourself, to whoever you choose. Neither
  contains a Social Security number or a vault photograph.
- **Your purchase status**, checked by Apple and RevenueCat.
  We never see a card number or any payment detail. The next section says
  exactly what those two receive and when.

## Purchases and Baby Docs Plus

Everything the plan itself is made of is free: every task, every deadline,
every document list, every official link, the two hard-deadline warnings,
and sending the plan to the other parent. Optional suggested-date
reminders, the Sunday digest and reminders you set yourself are Plus
features. The purchase-status check described here can happen whether or
not you buy Plus.

If you buy Plus, the purchase is made with Apple, and Apple's own privacy
policy covers it. To know whether Plus is active, the app uses
[RevenueCat](https://www.revenuecat.com/privacy/), which acts
as our processor. The app may make that check before a purchase so it can
restore an existing entitlement. What RevenueCat receives is:

- **An anonymous app user ID** generated by the SDK. It is a
  random identifier for a copy of the app on a device. We do not link it
  to your name, your email, your Apple Account or anything you entered in
  the app, because the app never sends any of that.
- **Purchase history**: which product was bought, when it
  started, whether a trial was used, whether it renewed, lapsed or was
  refunded, and the Apple receipt that proves it.
- **Basic technical context** sent with those calls: app
  version, iOS version, device model, and the country of your storefront.

In Apple's App Privacy vocabulary that is
*Purchases → Purchase History*, collected,
**not linked to your identity**,
**not used for tracking**, and used for two purposes: app
functionality, which is making what you paid for available, and analytics, which
is a dashboard of how many purchases, trials and refunds there were. It is
never sold, never shared with advertisers, and never joined to data from
other apps or websites. The app does not collect an advertising identifier
and does not ask RevenueCat to collect a device one.

**What RevenueCat never receives:** your child's name or
birth date, your state or county, your household answers, your plan, your
notes, your confirmation numbers, and every photograph in the document
vault. Those are not sent anywhere, by anything, ever.

**Keeping it and deleting it.** The purchase record is kept
for as long as the purchase can still matter. A lifetime purchase has to
be restorable on a new phone years later, which is the whole point of
"restore purchases", and the record is also part of the transaction
history Apple and we are required to keep. Deleting the app does not
delete it, and cannot: a record that vanished with the app is a record
that could not restore your purchase. If you want the RevenueCat record
for your copy of the app deleted, email the address at the bottom of this
page and we will delete it; be aware that doing so may mean a purchase can
no longer be restored automatically, and that Apple keeps its own record
either way.

Deadline reminders are scheduled by your own iPhone from dates it already
holds. There is no push notification service involved and no device token,
which is why reminders keep working with no signal at all.

If you tap “Use my location” on the household questions, iOS
gives the app a single position. The app asks Apple’s geocoding
service to resolve that position into a state and county, then discards
the position. Baby Docs does not store it or send it to its own server.
This helper is never used in the background.

## Who can see it

Your child, your household answers, your plan, your notes and your
documents: you, anyone holding your iPhone, and anyone you deliberately
send a plan or exported summary to. We have no database of any of it, so
there is nothing for us to look at, nothing to hand over and nothing to
breach.

If you use the location helper, Apple may process the one position needed
to return the state and county. Baby Docs does not receive a persistent
location history and does not keep the position.

Your purchase record: Apple, RevenueCat and us, as described above. It
says that a copy of the app bought a subscription. It does not say whose,
and nothing in it is about a child.

This is why the plan opens with no network: the moment you most need to
know which three documents the clerk is about to ask for is while you are
standing at the counter.

## What we do not do

- No advertising, no ad identifiers, no third-party trackers.
- We do not sell your family or app data or share it with advertisers.
  Purchase records are shared with Apple and RevenueCat as described
  above.
- We do not file, submit or transmit any government, tax, insurance or
  legal form on your behalf. The app links you to the official page and
  you file it yourself.
- We do not read, hold or connect to your health records, your insurance
  account, your bank or any government account.

## On Android

Baby Docs for Android follows every rule on this page, with Google in
place of Apple. Your answers, tasks, notes, confirmations and document
photographs stay in the app’s private storage on your phone and are
excluded from Google backups and device-to-device transfer, so a new phone
will not restore them. Photographs are added through Android’s own
photo picker; the app has no camera, storage, contacts or location
permission, and there is no location helper on Android. Reminders are
scheduled by your phone and never leave it.

If you buy Plus, the purchase is made with Google Play under Google’s
privacy policy, and RevenueCat receives the same anonymous app identifier,
purchase history and device details described above, with your Google
Play purchase token in place of the Apple receipt. Manage or cancel a
subscription in Google Play, Payments & subscriptions.

## Children

Baby Docs is for parents, and is not directed at children. The information
it holds about a child is the small set listed above, entered by that
child's own parent.

## Deleting things

- Archive a child or dismiss a task in the app and it leaves the active
  plan. The underlying record stays on the phone so you can restore it
  without losing completed work, notes or confirmations.
- Removing a document from the vault deletes the photograph from the phone
  immediately.
- Deleting the app removes everything it holds about your family. There is
  no account to close and no server copy of any of it to chase, because
  neither exists.
- The one thing deleting the app leaves behind is the purchase record held
  by Apple and RevenueCat, which is what lets a reinstall restore what you
  paid for. See Purchases and Baby Docs Plus for
  how to have ours deleted.

## Your rights

You can see and correct everything the app holds, export the one-page
summary as plain text, and permanently remove vault photographs from the
app. Archiving a child or dismissing a task hides it without destroying
the work attached to it. Deleting the app removes the remaining household
data from that iPhone without asking us.

## Changes

If this policy changes in a way that affects what is collected or who can
see it, the app will say so before the change takes effect.

Privacy questions:
[jackwallner+babydocs@gmail.com](mailto:jackwallner+babydocs@gmail.com)

[Support](https://jackwallner.com/ios/babydocs/support.html) ·
[Terms of Use](https://jackwallner.com/ios/babydocs/terms.html)

[Home](https://jackwallner.com/ios/babydocs/)
[Terms](https://jackwallner.com/ios/babydocs/terms.html)
[Support](https://jackwallner.com/ios/babydocs/support.html)
