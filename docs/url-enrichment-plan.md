# URL Enrichment Plan

## Goal

Make copied URLs more useful at recall time by enriching them with context automatically, while keeping Magpie lightweight and passive.

This should improve the core experience of scrolling back through history and remembering why a link mattered, without forcing users into an explicit bookmarking workflow.

## Product framing

Copied URLs are a strong intent signal. When someone copies a link, they are usually marking it as relevant in that moment. Magpie already captures that signal. Enrichment is about making the captured signal easier to understand and easier to revisit later.

The near-term objective is not to build a full URL management product. The near-term objective is to improve recognition, recall, and retrieval inside clipboard history.

## Phase 1: Basic URL enrichment

Focus: make copied links recognizable and scannable in history.

### 1. Detect URL clips automatically

Why this is helpful:
- URLs represent a different user intent than normal copied text.
- Automatic detection lets Magpie treat links as a first-class content type without adding user effort.
- This creates the foundation for every later enrichment feature.

### 2. Fetch page title

Why this is helpful:
- People remember the topic or page name, not the raw URL string.
- A title restores memory much faster than a bare link.
- This is the highest-value context signal with relatively low complexity.

### 3. Show site or domain name

Why this is helpful:
- Source context matters during recall.
- Domain recognition helps users distinguish similar links quickly.
- It improves trust and scanning even when page titles are weak.

### 4. Pull lightweight metadata where available

Examples:
- Open Graph title
- Open Graph description
- Preview image
- Favicon

Why this is helpful:
- Metadata turns a raw URL into a recognizable card.
- Even a short description can answer "what was this again?"
- A richer preview improves scrollability and visual differentiation in history.

### 5. Cache enrichment locally

Why this is helpful:
- Keeps the feature fast after the initial lookup.
- Avoids repeated network fetches for the same item.
- Supports the product goal of effortless retrieval after capture.

### 6. Handle failures gracefully

Examples:
- Metadata unavailable
- Site blocks scraping
- Request times out

Why this is helpful:
- Not every URL will enrich successfully.
- Reliable fallbacks prevent the feature from feeling inconsistent or fragile.
- A strong fallback preserves trust in the overall history experience.

Why Phase 1 supports the goal:

This phase delivers the clearest benefit with the least product risk. It improves recall immediately and keeps Magpie aligned with its core identity as a clipboard tool rather than expanding into a separate "save things for later" app.

## Phase 2: Better retrieval for enriched URLs

Focus: make enriched links easier to find after capture.

### 1. Add a URL-only filter or view

Why this is helpful:
- Users often want to recover a link specifically, not any clipboard item.
- A filtered view reduces noise in long histories.
- It strengthens the feeling that copied links are useful artifacts, not just raw text blobs.

### 2. Improve search using enriched fields

Searchable fields:
- Page title
- Site name
- Domain
- Description metadata

Why this is helpful:
- Users remember concepts and publishers more often than literal URLs.
- Enriched search increases successful retrieval and reduces frustration.
- It converts enrichment from visual polish into a real product advantage.

### 3. Improve list presentation for URL clips

Why this is helpful:
- Better hierarchy makes scanning faster.
- Richer presentation helps links stand out among plain text clips.
- This reinforces the overall goal of making copied URLs recognizable at a glance.

### 4. Group repeated copies of the same URL

Why this is helpful:
- Repeated copies create clutter.
- Grouping improves signal quality without losing history.
- Repeat copies may also indicate importance, which could become useful later.

### 5. Emphasize time context

Examples:
- Copied today
- Copied yesterday
- Exact timestamp

Why this is helpful:
- Time is often part of how users remember a copied link.
- It helps reconstruct the original context of use.
- It supports recall without adding new workflows.

Why Phase 2 supports the goal:

Phase 1 makes URL history richer. Phase 2 makes that richness actionable. This is the point where enrichment starts materially improving retrieval rather than just making history look nicer.

## Phase 3: Lightweight intent signals

Focus: preserve more context around why the user copied a URL in the first place.

### 1. Capture source app when possible

Examples:
- Slack
- Safari
- Mail
- Notes

Why this is helpful:
- Source app is often enough to reconstruct intent.
- "Copied from Slack" suggests very different relevance than "copied from Safari."
- This adds context without asking users to annotate anything manually.

### 2. Surface stronger relevance signals

Examples:
- Re-copied URLs
- Frequently revisited URLs
- Recently copied clusters

Why this is helpful:
- Repetition is a useful proxy for importance.
- These signals can help Magpie highlight what mattered without creating a formal bookmark flow.
- It moves the product toward intent-aware recall while staying passive.

Why Phase 3 supports the goal:

This phase deepens context around copied links without requiring users to actively organize them. It improves Magpie's usefulness by making clipboard history feel more aware of user intent.

## Later to think about

These ideas are interesting, but they should follow proof that basic enrichment and retrieval are already valuable.

### Summarizer

Why it could be helpful:
- Some titles are vague, generic, or SEO-heavy.
- A one-line summary could better answer the question, "Why did I copy this?"
- It could make Magpie feel significantly smarter for content-heavy links.

Why it should come later:
- It adds cost, latency, and privacy considerations.
- Summaries can be wrong or low quality.
- Basic metadata may solve most of the recall problem without introducing AI-specific complexity.

### URL manager

Why it could be helpful:
- A dedicated view for collected links could create a stronger revisit workflow.
- Organization features such as tagging, categorization, or reading-list style behavior may appeal to power users.
- It could open a broader product direction around passive bookmarking.

Why it should come later:
- It risks turning Magpie into a different product category.
- Saved-link products often suffer from low revisit rates, so the value needs to be proven carefully.
- The current opportunity is stronger around effortless capture plus recall than active link management.

## Guiding principles

- Enrichment should feel passive, fast, and low-friction.
- The first job is recall, not content consumption.
- Retrieval should improve before Magpie takes on heavier organizational behavior.
- Each phase should strengthen Magpie's identity as a clipboard tool.
