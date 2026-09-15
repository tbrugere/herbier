# Claude Design prompt — Herbier

> Paste everything below the line into Claude Design. It deliberately describes
> intent and capabilities only; screens, navigation and visual language are left
> to the design tool.

---

## What this is

Design an Android app called **Herbier**: a personal, single-user field herbarium.
I use it to keep a record of the plants I have met, where I met them, the photos
I took, and my own notes on each of them. It is a private collection, not a social
app, and not a plant identification tool.

The mental model is a **collection of plants I care about**, each with a rich
species page. Pl@ntNet's species description pages are the closest reference for
the "rich species page" feeling: names, photo gallery, botanical information,
distribution, links out. Herbier adds to that what Pl@ntNet lacks: the ability to
**save a plant as mine**, attach **my own** photos, locations, notes and tags, and
**browse my collection**.

## Who it is for

One person (me), using it mostly outdoors on a phone, often one-handed, sometimes
with poor connectivity. Later, sitting at home, reviewing and annotating what I
recorded. Assume a botanically curious amateur: comfortable with Latin names, but
wants the localized common name (French first) shown prominently too.

## Core entities

- **Plant** (a species I have saved). Has:
  - scientific name and localized common name(s)
  - identifiers / links to external references: GBIF taxon, Pl@ntNet species page,
    Wikipedia article, possibly Kew POWO and EPPO codes
  - my personal notes (free text, editable over time)
  - tags (free-form, user-created, reusable across plants)
  - one or more **observations**
- **Observation** (one encounter with that plant). Has:
  - a location (GPS point, with optional place label), taken at record time or
    picked on a map afterwards
  - a date
  - zero or more photos I took
  - an optional short note specific to that encounter
- **Tag**: a user-defined label, used for filtering and browsing.

## Capabilities the design must cover

### Recording
- Quickly record a new plant in the field: take or pick photos, capture current
  location, type or pick the species name. Speed and low friction matter most here.
- Add a new observation to an already-saved plant (I met it again elsewhere).
- Edit notes, tags, names and links at any time.
- Photos are stored compressed and size-limited; the design can assume a modest
  number of photos per plant (typically 1–10).

### Species page (the heart of the app)
- For each saved plant, one place that merges **my data** (photos, observations,
  notes, tags) with **reference data** fetched from external sources:
  - names: scientific, synonyms, vernacular names in several languages
  - taxonomy / classification
  - reference photos from external sources (distinct from my own photos)
  - descriptive text (e.g. Wikipedia summary)
  - distribution / occurrence overview (e.g. from GBIF)
  - outbound links to the source pages (GBIF, Pl@ntNet, Wikipedia, others)
- Make it clear what is mine and what comes from an external source.
- Reference data may be missing, partial, or unavailable offline; the page must
  still be useful with only my own data.

### Browsing the collection
- Browse all my saved plants; search by any name.
- Filter and group by tag.
- Browse by location: a map of all observations, and the ability to go from a
  place to the plants seen there and back.
- Browse by time (when I recorded things).

### Intercepting links from other apps
- Plant identification is out of scope. Instead, when I identify a plant in
  Pl@ntNet and share or open one of its outbound links (to GBIF, to Pl@ntNet's
  own species pages, etc.), Herbier should catch that link, resolve it to a
  species, and offer to save it as a new plant, pre-filled with names and
  reference links. This is a primary way plants get into the collection, so it
  deserves a smooth flow.
- The same "resolve a link/name into a species" capability should be available
  from inside the app (paste a link, or search a name).

### Reference lookups
- When creating a plant, name search should propose matching species from a
  reference source with scientific + common names so I can pick the right one.
- Once a plant is linked to an external identifier, reference data is fetched
  and cached; refreshing it should be possible but not something I do often.

## Constraints and non-goals

- Android only, phone form factor, portrait first.
- Single user. No accounts to manage beyond a one-time sign-in, no sharing, no
  social features, no comments, no likes.
- No plant identification from photos.
- Free-tier backend: keep data and images light; no expectation of unlimited
  storage or heavy media.
- Photos may live in my own Google Photos or Google Drive account rather than
  in the app's backend. The design should accommodate photos being linked from
  there (a one-time Google sign-in, photos picked from or saved to my library,
  possibly slower to load than local ones), and should not assume the app
  owns the images.
- Must degrade gracefully offline: recording (photos, location, notes) should
  never be blocked by connectivity; reference data can arrive later.
- Interface language: French UI with Latin names; design copy can be in French
  or English, whichever is easier, but keep in mind French labels are longer.

## Tone

Calm, field-notebook / herbarium feeling rather than a consumer social app.
Photos and names should take precedence over chrome. Dense information is fine
on the species page; recording should feel light and fast.

## What I want from you

Propose the app's information architecture, screens and flows that cover all
the capabilities above, then mockups for the key screens. Decide yourself on
navigation structure, page breakdown, and visual language. Flag any capability
above you think is unclear or in tension with another.
