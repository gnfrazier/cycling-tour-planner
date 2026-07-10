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

| **Role**               | **Tone / Description**          | **Use Case**                                                                     |
| ---------------------- | ------------------------------- | -------------------------------------------------------------------------------- |
| **Primary Base**       | Deep Slate Blue (`#1A2332`)     | Used for deep planning layouts on Desktop/Web; softens eye strain indoors.       |
| **High-Contrast Dark** | Absolute Obsidian (`#0D1117`)   | Used for the Mobile/Outdoor interface to maximize sunlight legibility.           |
| **Primary Light**      | Alabaster Parchment (`#F4F3EF`) | A subtle, classic off-white used for cards, menus, and clean light-mode layouts. |
| **Stark Light Accent** | Pure Crisp White (`#FFFFFF`)    | Reserved for critical outdoor typography and icons against dark bases.           |
| **Muted Neutral**      | Topo Gray (`#707884`)           | Used for subtle secondary text, grid borders, and non-critical map layers.       |

### Routing Theme Semantics

The UX design requires that colors communicate meaning across all platforms (e.g., what a theme color signifies). These subtle, sophisticated jewel tones represent the five P0 MVP route constraints:

- **The Flattest Theme:** **River Valley Teal** (`#1E5E60`)
    
    - _Vibe:_ Calm, low-resistance, following the path of least elevation gain.
        
- **The Most Climbing Theme:** **Ridge Line Terracotta** (`#B85A38`)
    
    - _Vibe:_ Earthy, challenging, high-altitude training.
        
- **The Lowest Traffic Theme:** **Serene Forest Green** (`#2D5236`)
    
    - _Vibe:_ Safe, quiet, isolated rural routing.
        
- **The Fewest Turns Theme:** **Linear Horizon Blue** (`#2E5B88`)
    
    - _Vibe:_ Uninterrupted, straight-line momentum.
        
- **The Most Art/History Theme:** **Curated Burgundy** (`#722F37`)
    
    - _Vibe:_ Rich, cultural, anchoring points of interest and architectural landmarks.
        

## Interface Adaptability & Contrast Modes

As dictated by the ecosystem guidelines, the app must transition flawlessly between comfortable indoor planning and harsh outdoor field execution.

### 1. Indoor Contrast Mode (Desktop & Web Defaults)

- **Application:** Full-screen desktop displays during deep planning sessions.
    
- **Execution:** Uses richer, slightly softer contrasts (Primary Base over Alabaster Parchment). Information density is maximized to present lodging details, multi-day mileage splits, and weather data concurrently without clutter.
    

### 2. Outdoor Contrast Mode (Mobile Default & Full-Screen Toggle)

- **Application:** On-the-bike mobile execution, handlebar mounts, and quick trailhead checks.
    
- **Execution:** Drops all subtle mid-tones. Switches to high-contrast monochrome dark mode (Absolute Obsidian background paired with Pure Crisp White text).
    
- **Theme Integration:** Route lines use the full saturation of their designated theme color accompanied by a high-contrast white border to separate the line cleanly from base map tiles.
    

## Graphic & UI Elements

To maintain a sophisticated and classic aesthetic without sacrificing single-thumb utility:

> **Iconography & Borders:** Use crisp, uniform, single-weight vector outlines rather than filled shapes or playful illustrations. Map layers and POI pins should resemble traditional, professional survey maps rather than a gamified app interface.

> **UI Component Shape:** Buttons and cards feature crisp, subtle corners (small border-radius) rather than pills or aggressive rounded shapes, anchoring the design in classic cartographic layouts. Tap targets remain oversized to account for handlebar vibration and gloved hands, hiding their large functional size behind subtle visual alignment.