# AI Development Log — Velouré Patisserie

This file records what I asked the AI to do and where it got things wrong or needed correcting.
It supports two parts of the video: "what you asked AI to do" (40 pts) and "troubles using AI" (20 pts).
**Keep adding to it** as you test, customize and fix things.

AI tool used: Claude (claude.ai), with files written directly into `~/veloure` on my Mac.

---

## What I asked the AI to do

| # | My request | Result |
|---|---|---|
| 1 | Walk me through the midterm step by step | Roadmap of 7 steps |
| 2 | Pick a topic not related to my group's Health & Joy Café | Several rounds of ideas (tech store, plants, hot sauce, recipes, jams) until I chose my own direction |
| 3 | Read an Instagram dessert shop and make something similar, with a different name, in New Jersey | AI **could not open Instagram**, so I sent ~90 screenshots in Albanian, which it translated |
| 4 | Make everything vegan; use only natural sweeteners; cocoa butter instead of butter; everything homemade (nut butters, tahini, jams, fruit pastes) | Built the 40-product menu |
| 5 | Name: short, unique, high-end, no "&" | Chose **Velouré Patisserie**, slogan "Sweet by nature." |
| 6 | Make a logo | 3 SVG versions; I picked the light one |
| 7 | Marketing copy: Vegan, Gluten-Free, Sugar-Free, "Artisanal", explain the name, keep recipes secret | Homepage, About page, product descriptions |
| 8 | Build the website with Docker (web + database) | Flask + PostgreSQL, 2 containers, 8 page types, admin dashboard |

---

## Troubles and corrections

**Wrong or questionable content from the AI**
- It first suggested **honey** as a sweetener, but honey is **not vegan**. I removed it.
- It put a **honey emoji** on the "No Refined Sugar" badge even after honey was removed. I asked for **no emojis at all**.
- It described the brand as **"luxury."** I asked it to remove that and let customers judge.
- It included a **specific street address in Montclair**. I changed it to "Bergen County, New Jersey" only.
- I asked for **"Sugar-Free"**. The AI warned that in the US "sugar-free" has a legal meaning (under 0.5 g of sugar per serving). Fruit- and date-sweetened desserts don't qualify, so we used **"No Refined Sugar."**
- It suggested **monk fruit**. I didn't know what it was and removed it to keep ingredients familiar.
- Its first product descriptions listed every ingredient. I asked it to **keep recipes secret** and say only "natural ingredients."

**Broken or missing functionality found while testing**
- The newsletter message promised a **10% discount code that the app never applied**. This was a hallucinated feature, so I removed the promise.
- Category tiles had **white text on a light background** when photos didn't load. The AI added a dark overlay.
- Many photo search results were **Unsplash+ (paid license)**, not free. They had to be rejected and only free-license photos used.

**Setup and command problems**
- `docker` gave **"command not found"** until Docker Desktop was opened for the first time.
- The AI's instructions used `docker start <ID>`. I typed `<ID>` literally and got **`zsh: parse error`**, because it was a placeholder. Fix: use the container name `it310-instance`.
- I typed `exit` one extra time and it **closed the whole Terminal** ("Process completed").
- The Tech Setup uses `sudo`, which isn't needed with Docker Desktop on a Mac.
- Port **5000** is often taken on Macs by **AirPlay Receiver**, so the site uses **8080** instead.

**Add your own as you go:** anything that breaks when you run it, anything you change by hand, and anything the AI explained wrong.

---

## Round 2: real menu, photos and business rules

**What I asked the AI to do**
- Replace the sample menu with my real menu (from my Albanian price list) and my own product photos (54 photos). The AI translated everything to English and wrote a description for each product.
- Rename products without using trademarked candy names (Snickers → Peanut Caramel Bar, Mars → Pistachio Caramel Truffles, Ferrero Rocher → Hazelnut Crunch Truffles, Raffaello → Coconut Raspberry Snowballs).
- Sizes: Medium (serves 4) and Large (serves 6–8) for cakes; by the piece or by the box for bites.
- Orders at least 24 hours in advance; booking up to 30 days ahead; cancel within 6 hours.
- Free delivery from $55; payment choice (Visa, Mastercard, Amex, Apple Pay, Google Pay, PayPal), simulated.
- Velouré Family accounts: 10% off first order, coupons, points, birthday gift box, emails about coupons and new flavors.
- Remove drinks, jars, the tart category, and the reviews section.

**Troubles and corrections**
- The AI matched my photo numbers to the wrong list ("3 and 4" from my menu vs. its own numbered list), so I had to correct it.
- The AI labeled my trileçe as vegan, but my real recipe uses eggs, honey and Greek yogurt. It pointed out the conflict with the "100% vegan" promise and described a vegan version instead.
- I generated gift box photos with another AI image tool; the logo it drew on the box is slightly different from my real logo.
- Bug found while testing: the size buttons and Add to Cart button were squeezed side by side on the product page; the CSS had to be fixed.
- Bug found while testing: the test browser refused port 5060 (an "unsafe" port in Chrome), so the AI had to test on another port.
- Emails can't really be sent from a class prototype without an email service, so they are saved to an `email_outbox` table and shown in the dashboard instead.
- The AI would not add customer reviews unless they were the customers' original messages, so I removed the reviews section.
- Python's time zone support needed the extra `tzdata` package inside the slim Docker image, otherwise the 24-hour rule can't use New Jersey time.

**Add your own:** anything that breaks when you run it on your Mac, and anything you change yourself.

---

## Ideas for the group final project (the last 20-point section)

- **Keep:** Docker Compose with separate web and database containers; the `/health` check; database transactions at checkout; stock that decreases automatically.
- **Redesign:** real customer accounts (sign-up, login, order history) instead of only an admin password; cart saved in the database instead of a cookie.
- **Add:** a promo-code table so discounts work for real; email confirmations; image uploads in the admin page instead of image links.
- **Approach differently:** check AI output against official sources (licenses, legal labels like "sugar-free," allergens); test every feature the AI claims exists; keep this log from day one.
