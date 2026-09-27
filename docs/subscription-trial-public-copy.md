# 7-day trial / new access model — public copy and App Review notes

Status: **approved wording, not yet applied.** Nothing here has been changed on
comigo.net or in App Store Connect. Apply when build 200 (the first new-model
build) is submitted.

## In-app rule
The app only says "Start your 7-day free trial" / "Try Comigo free for 7 days"
after StoreKit confirms `isEligibleForIntroOffer` for the Monthly product
(paywall, Library banner, locked-episode button, Settings). Trial length and
prices always come from StoreKit.

## App Store description
Replace the section "THE FIRST EPISODE OF EVERY SERIES IS FREE" with:

> TRY COMIGO FREE FOR 7 DAYS
> Eligible new subscribers can get 7 days of full access to every episode and learning feature. After the trial, Comigo Unlimited renews automatically as a monthly subscription unless cancelled. Lifetime access is also available as a one-time purchase.

(No mention of grandfathering in public copy.)

## What's New (build 200 release)
> New: eligible new subscribers can try Comigo Unlimited free for 7 days.

## App Store screenshots
Collection screenshot caption: use **"Follow the story episode by episode"** in
every set, replacing "The first episode of every series is free". The 6.9″
iPhone set (`shots/appstore-iphone-captioned/03-collection.png` in the
generator repo) currently only has the old caption; the 6.5″ and iPad sets have
`03-collection-fixed.png`. Check which images are live in App Store Connect.

Also check the Monthly product's description in App Store Connect for any
free-episode wording.

## comigo.net (generator repo `site/`)
| Where | Current | Replace with |
|---|---|---|
| `spanish-reading-practice.template.html` band, and `example-page.html` band (all example pages) | "One complete comic is free." | "Eligible new subscribers can try Comigo free for 7 days." |
| `index.template.html` | "For iPhone and iPad. Free to start." | "For iPhone and iPad. 7-day free trial for eligible new subscribers." |
| "Try Comigo free" buttons (learn-spanish-with-comics ×2, visual-learning-language) | "Try Comigo free" | **Keep** — the website can't know an account's trial eligibility. |

## App Review notes (draft, for the build 200 submission)
> This version introduces a 7-day free introductory offer on Comigo Unlimited Monthly for eligible new subscribers. Customers who originally downloaded Comigo before this version (AppTransaction.originalAppVersion below build 200) keep their existing access: the first episode of every series remains free for them. Customers who first download this version or later can browse the library, and reading requires an active free trial, subscription or the lifetime purchase. Trial eligibility, trial state and entitlement come entirely from StoreKit. Restore Purchases is available on the paywall and in Settings → Subscription.
>
> To review the new-customer experience in the sandbox, no special steps are needed: sandbox installs are treated as new customers by default (Settings → Diagnostics → "Access model (testing)" switches between new-customer and existing-customer behaviour; this control only appears in sandbox/TestFlight builds).

## App Store Connect setup (before releasing build 200)
- Monthly product → Introductory Offers → **Free, 1 week, new subscribers**, all territories. Releasing build 200 without it would leave new customers locked with no trial offered.
