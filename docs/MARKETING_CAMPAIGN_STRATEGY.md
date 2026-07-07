# Marketing Campaign Strategy — Small / Medium / Large

**Goal:** get `heartbeat_wrap` in front of people who'd actually use it
(devs, DevOps/CI folks, AI-coding-agent users) so some fraction try it,
star it, and — per the existing README "Support this project" section —
tip a few dollars via the PayPal link. Not a growth-hacking plan; a
realistic, low-effort-first funnel that scales with whatever time/budget
you're willing to put in.

**Audience is narrower than "developers in general."** The strongest,
most specific hook is: *"AI coding agents (Cline, Copilot, Cursor, CI
runners) can't tell 90%-done from truly-stuck — this fixes that."* That
angle is unique to this tool and should lead every pitch, not "yet
another terminal heartbeat script."

**Before spending anything, two free conversion improvements:**
1. Add a **Buy Me a Coffee** button alongside the PayPal link — it's
   purpose-built for small one-off tips (lower friction than PayPal for
   a stranger who just found your repo), and its badge renders nicely at
   the top of a README.
2. Move the "Support this project" section (currently near the bottom of
   `README.md`) into a small badge row right under the title, next to
   the license badge — most traffic never scrolls to the bottom.

---

## 🟢 Small Tier — $0 budget, a few hours of your time

**Channel list (all free, all one-time posts):**
- **Show HN** on Hacker News — lead with the AI-agent-hang angle
  specifically, since that's the freshest/least-crowded pitch on HN right
  now (most "terminal heartbeat" tools predate the agentic-coding wave).
- **Reddit**: `r/commandline`, `r/bash`, `r/devops`, `r/programming` (one
  well-written post each, spaced a few days apart — cross-posting
  simultaneously reads as spam and gets removed).
- **Cline's own Discord/community + `r/cline`-equivalent spaces** — this
  is the single best-fit audience of all of them, since the repo already
  ships a working `Cline` MCP server integration. Post there first.
- **`awesome-*` GitHub list PRs** — `awesome-bash`, `awesome-cli-apps`,
  `awesome-devops`, and (most relevant) any `awesome-mcp-servers` /
  `awesome-cline` list. Free, permanent, evergreen discovery surface —
  low effort, don't skip this one.
- **dev.to / Hashnode post** — a short "why does my AI agent think a
  hung command is still running?" write-up, ending with the repo link.
- **One X/Twitter or Bluesky post** with a short terminal-recording GIF
  (`asciinema` or a screen recording) showing the heartbeat lines
  scrolling — visual proof beats prose for a CLI tool.

**Cost:** $0. **Time:** a weekend, spread over ~2 weeks so posts don't
collide. **Success metric:** GitHub stars trend + any PayPal/BMC tips at
all (even $5–20 total validates the funnel before spending real money).

---

## 🟡 Medium Tier — modest budget (~$100–300, one focused push)

Only worth doing once the Small tier has already produced *some* organic
signal (stars, comments, a tip or two) — spending money to promote
something with zero validated interest is a waste either way.

- **Product Hunt launch** — free to list, but budget ~$50–100 for a
  decent launch-day graphic/short demo video (Fiverr or a couple hours in
  a free screen-recorder + GIMP/Canva). Needs a specific launch day and a
  few people primed to upvote early (timing matters more than budget
  here).
- **Sponsor one small dev newsletter** — things like a niche
  CLI-tools/devops-tools newsletter (not the mega ones yet — a
  10–30k-subscriber niche newsletter is both cheaper and more targeted
  than a 200k general one at this budget). Typical sponsor slot: $50–150.
- **Boost the single best-performing organic post** from the Small tier
  (whichever Reddit/X post got the most genuine engagement) with a small
  $30–50 ad spend on that same platform, rather than writing new ad copy
  from scratch — you already know it resonated.
- **Set up GitHub Sponsors** with 2–3 small tiers (e.g. $3/mo "coffee,"
  $10/mo "named in README") alongside the existing PayPal/BMC links —
  recurring small support compounds better than one-off tips once there's
  a real, if small, user base.

**Cost:** ~$100–300 total. **Time:** ~1–2 weeks of prep, concentrated
around the Product Hunt launch day. **Success metric:** a real uptick in
clones/stars that week, and whether GitHub Sponsors gets *any* recurring
signups (tells you if it's worth a Large-tier push later).

---

## 🔴 Large Tier — real budget (~$500–2,000+), only after Medium validates

Don't jump here unless the smaller tiers already showed genuine pull —
this tier assumes there's something worth amplifying, not something to
discover interest for the first time.

- **Podcast ad spot or dev-newsletter sponsorship at scale** — e.g. a
  slot on a well-known dev/DevOps podcast (Changelog-tier, Software
  Engineering Daily-tier) or a bigger newsletter (Bytes, TLDR Dev-tier).
  Typical cost for a single spot: several hundred to ~$1–2k depending on
  audience size — get quoted rates directly, they vary widely.
- **Targeted content marketing, not just ads:** commission (or write
  yourself, budgeting your own time as the cost) 2–3 solid technical blog
  posts specifically about the AI-agent-hang problem, pitched as guest
  posts to sites that accept them (freeCodeCamp, dev.to's featured
  queue) — content that ages well and keeps bringing search traffic long
  after a one-off ad would've stopped.
- **A short paid demo video** (30–60s) for a CLI-tools-focused YouTube
  Shorts/TikTok creator to feature, rather than buying generic display
  ads — dev tools sell far better through a trusted creator's own
  audience than through cold ad impressions.
- **Paid listing in curated dev-tool directories** (terminal/CLI-tool
  roundup sites) — cheap relative to the rest of this tier and compounds
  with the `awesome-*` list placements from the Small tier.

**Cost:** $500–2,000+, scaling with how far you want to take it.
**Time:** ongoing, not a single push — this tier is really "graduate to
a recurring, budgeted marketing motion" rather than a one-time campaign.
**Success metric:** whether GitHub Sponsors/PayPal/BMC recurring income
starts approaching what you're spending — if it doesn't by the end of
one full push, that's a real signal to scale back down to Medium/Small
rather than keep escalating spend.

---

## Sequencing summary

Small (free) → validate real interest exists → Medium (~$100–300,
concentrated push) → validate people will actually pay/tip/sponsor →
only then Large (~$500–2,000+, ongoing). Skipping straight to Large
without Small/Medium validation is the single most common way this kind
of campaign burns money without result — resist the urge to jump ahead
even if a specific opportunity (podcast slot, etc.) looks tempting early.
