# Brand Identity Guide: Cycle Tour Planner

This guide establishes the visual and emotional framework for **Cycle Tour Planner**. It balances a **classic, sophisticated, and subtle** aesthetic with the rugged, absolute legibility required by high-stress outdoor environments.

## Brand Sentiment & Personality

The brand tone speaks to the intentional cyclist—whether a Professional Tour Planner mapping out a client logistics route or a Weekend Outing Cyclist seeking a rural escape. It avoids flashy, over-stimulating fitness app tropes (no neon yellows or aggressive "segment-chasing" language). Instead, it leans into understated expertise and reliability.

- **Understated Expertise:** Thoughtful, precise, and highly functional. The app feels like a beautifully crafted tool rather than a social media feed.
    
- **Grounded & Reliable:** Rooted in local-first data, offline certainty, and cartographic tradition.
    
- **Sophisticated Adventure:** Celebrates the geometry of a perfect loop, the quiet of a low-traffic rural road, and the curation of cultural routes.
    

## Color Palette & Semantic System

To fulfill the UX requirement for **High-Contrast Visual Systems** while maintaining a classic and subtle tone, the color strategy uses a deep, rich foundation paired with crisp, purposeful accents. The system splits into foundational adaptive modes (Indoor vs. Outdoor) and a semantic layer specifically for the five core routing themes.

### Foundational Colors

| **Swatch** | **Role**               | **Tone / Description**          | **Use Case**                                                                     |
| ---------- | ---------------------- | ------------------------------- | -------------------------------------------------------------------------------- |
| ![#1A2332](assets/swatches/1A2332.svg) | **Primary Base**       | Deep Slate Blue (`#1A2332`)     | Used for deep planning layouts on Desktop/Web; softens eye strain indoors.       |
| ![#0D1117](assets/swatches/0D1117.svg) | **High-Contrast Dark** | Absolute Obsidian (`#0D1117`)   | Used for the Mobile/Outdoor interface to maximize sunlight legibility.           |
| ![#F4F3EF](assets/swatches/F4F3EF.svg) | **Primary Light**      | Alabaster Parchment (`#F4F3EF`) | A subtle, classic off-white used for cards, menus, and clean light-mode layouts. |
| ![#FFFFFF](assets/swatches/FFFFFF.svg) | **Stark Light Accent** | Pure Crisp White (`#FFFFFF`)    | Reserved for critical outdoor typography and icons against dark bases.           |
| ![#707884](assets/swatches/707884.svg) | **Muted Neutral**      | Topo Gray (`#707884`)           | Used for subtle secondary text, grid borders, and non-critical map layers.       |

### Routing Theme Semantics

The UX design requires that colors communicate meaning across all platforms (e.g., what a theme color signifies). These subtle, sophisticated jewel tones represent the five P0 MVP route constraints:

- ![#1E5E60](assets/swatches/1E5E60.svg) **The Flattest Theme:** **River Valley Teal** (`#1E5E60`)
    
    - _Vibe:_ Calm, low-resistance, following the path of least elevation gain.
        
- ![#B85A38](assets/swatches/B85A38.svg) **The Most Climbing Theme:** **Ridge Line Terracotta** (`#B85A38`)
    
    - _Vibe:_ Earthy, challenging, high-altitude training.
        
- ![#2D5236](assets/swatches/2D5236.svg) **The Lowest Traffic Theme:** **Serene Forest Green** (`#2D5236`)
    
    - _Vibe:_ Safe, quiet, isolated rural routing.
        
- ![#2E5B88](assets/swatches/2E5B88.svg) **The Fewest Turns Theme:** **Linear Horizon Blue** (`#2E5B88`)
    
    - _Vibe:_ Uninterrupted momentum — one road, no decisions, however it bends.
        
- ![#722F37](assets/swatches/722F37.svg) **The Most Art/History Theme:** **Curated Burgundy** (`#722F37`)
    
    - _Vibe:_ Rich, cultural, anchoring points of interest and architectural landmarks.
        

## Interface Adaptability & Contrast Modes

The app carries one identity, dressed for the conditions. Rather than a manual light/dark toggle, it runs a single **adaptive contrast system** that senses context — device type, viewport size, and, where the platform exposes it, ambient light or the OS's own light/dark setting — and defaults intelligently, so most riders never have to think about it. The two modes below are that same design language wearing two different outfits, not two disconnected interfaces.

### 1. Indoor Contrast Mode (Desktop & Web default)

- **Application:** Full-screen desktop and Web displays during deep planning sessions — the system's default read of a comfortable, well-lit, indoor context.
    
- **Execution:** Uses richer, slightly softer contrasts (Primary Base over Alabaster Parchment). Information density is maximized to present lodging details, multi-day mileage splits, and weather data concurrently without clutter.
    

### 2. Outdoor Contrast Mode (Mobile default; available on Desktop/Web)

- **Application:** On-the-bike mobile execution, handlebar mounts, and quick trailhead checks — always the default on Mobile, since that context is never ambiguous.
    
- **Execution:** Drops all subtle mid-tones. Switches to high-contrast monochrome dark mode (Absolute Obsidian background paired with Pure Crisp White text).
    
- **Theme Integration:** Route lines use the full saturation of their designated theme color accompanied by a high-contrast white border to separate the line cleanly from base map tiles.
    

### Manual Override

Desktop and Web can be handed a context the automatic system reads wrong — a Professional Tour Planner working from a laptop at a sun-exposed trailhead, say. A manual switch exists there as an **override for when the automatic choice is wrong**, not as the primary way most people interact with contrast. Reaching for it should feel like adjusting the room's lighting, not flipping an app setting.

An explicit override is an **account-level preference that syncs** across the user's signed-in devices — set it once and it's already reflected the next time contrast needs correcting elsewhere. The *automatic* default is never overridden by this saved state; it's evaluated fresh per surface, since Mobile's context (always outdoor) and Desktop/Web's context (usually indoor, sometimes not) aren't the same question.

## Graphic & UI Elements

To maintain a sophisticated and classic aesthetic without sacrificing single-thumb utility:

> **Iconography & Borders:** Use crisp, uniform, single-weight vector outlines rather than filled shapes or playful illustrations. Map layers and POI pins should resemble traditional, professional survey maps rather than a gamified app interface.

> **UI Component Shape:** Buttons and cards feature crisp, subtle corners (small border-radius) rather than pills or aggressive rounded shapes, anchoring the design in classic cartographic layouts. Tap targets remain oversized to account for handlebar vibration and gloved hands, hiding their large functional size behind subtle visual alignment.