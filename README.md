# Velouré Patisserie

---

## 1. Run it

Docker Desktop must be open (whale icon in the menu bar).

```bash
cd ~/veloure
docker compose down -v          # only needed if you ran an older version before (resets the database)
docker compose up --build
```

Open **http://localhost:8080** when you see `Booting worker`.

| What | Command |
|---|---|
| Stop | `Control + C`, then `docker compose down` |
| Start again (no file changes) | `docker compose up` |
| Reset database to the original menu | `docker compose down -v` then `docker compose up --build` |

* **Staff dashboard:** http://localhost:8080/admin, password `veloure-admin`
* **Health check:** http://localhost:8080/health

---

## 2. Architecture

```
  Your browser
      |  http://localhost:8080
      v
+-----------------------------+        veloure-net (private Docker network)
|  veloure-web  (container)   |  ---------------------------------------+
|  Python 3.12 + Flask        |   connects to  db:5432                  |
|  Gunicorn web server :5000  |                                         v
|  + product photos (static)  |                       +-----------------------------+
+-----------------------------+                       |  veloure-db  (container)    |
                                                      |  PostgreSQL 16              |
                                                      |  data in volume             |
                                                      |  "veloure-data"             |
                                                      +-----------------------------+
```

* **veloure-web** is built from `web/Dockerfile`. Mac port **8080** → container port **5000**.
* **veloure-db** uses the official `postgres:16-alpine` image. On first start it runs `db/init.sql`: 9 tables, 9 categories, 79 products, 129 sizes/prices, and one coupon.
* The web app reaches the database by the name **`db`** (Docker DNS on `veloure-net`, see `DATABASE_URL` in `docker-compose.yml`).
* The database has **no published port**, so only containers on `veloure-net` can reach it.
* `depends_on: condition: service_healthy` makes the web container wait for Postgres' `pg_isready` check.

### Useful Docker commands

```bash
docker compose ps                              # both containers, ports, health
docker ps -a                                   # Tech Setup command
docker images                                  # the veloure-web image you built
docker network ls
docker network inspect veloure_veloure-net     # both containers and their IPs
docker volume ls                               # veloure_veloure-data
docker compose logs web                        # Gunicorn + every page request
docker compose logs db                         # Postgres running init.sql
docker exec -it veloure-web bash               # inside the web container (exit to leave)
docker exec -it veloure-db psql -U veloure -d veloure    # open the database (\q to leave)
```

Useful SQL inside `psql`:

```sql
\dt
SELECT name, stock FROM products ORDER BY stock LIMIT 5;
SELECT p.name, v.label, v.price FROM product_variants v JOIN products p ON p.id = v.product_id WHERE p.slug = 'veloure-cake';
SELECT order_number, customer_name, payment_method, discount_label, total, status FROM orders;
SELECT name, email, points, birth_month FROM users;          -- passwords are stored only as hashes
SELECT kind, to_email, subject FROM email_outbox ORDER BY id;
```

---

## 3. Pages and features

| Page | URL |
|---|---|
| Home | `/` |
| Shop (catalog) | `/shop` |
| Product detail | `/product/<name>` e.g. `/product/veloure-cake` |
| Cart | `/cart` |
| Checkout | `/checkout` |
| Order confirmation | `/order/VL-10001` |
| Manage my order | `/manage-order` |
| Join / Sign in / My account | `/join`, `/login`, `/account` |
| About us | `/about` |
| Staff dashboard | `/admin` |

**Major e-commerce features**

1. **Catalog with search, filters, sorting** (`shop()` in `app.py`): category, Nut-Free, Caffeine-Free, Seasonal, Best Sellers, Available to order. Builds a SQL `WHERE` clause with safe `%s` parameters.
2. **Product sizes / variants** (`product_variants` table): cakes in Medium (serves 4) or Large (serves 6–8); bites by the piece or by the box. Each size has its own price.
3. **Shopping cart** (`cart_*` routes): stored in the session as `{variant_id: quantity}`; stock is shared by all sizes of a product.
4. **Checkout simulation with business rules** (`checkout()`, `place_order()`):
   * **24-hour rule**: the chosen time slot must start at least 24 hours from now (NJ time), up to 30 days ahead.
   * Pickup or Bergen County delivery (ZIP 07xxx); delivery $8, free from $55.
   * Payment method choice (Visa, Mastercard, Amex, Apple Pay, Google Pay, PayPal, Pay at pickup), **simulated, no charge**.
   * One **database transaction**: lock rows (`FOR UPDATE`), check stock, insert order + items, lower stock, update points, `COMMIT` (or `ROLLBACK`).
5. **Cancellation within 6 hours** (`cancel()`, `cancel_order()`): restores stock and points. Customers find orders at **Manage my order** (order number + email).
6. **Velouré Family accounts (authentication)**: sign-up with hashed passwords (`werkzeug.security`), login, account page.
   * 10% off the first order, member coupons (e.g. `AUTUMN15`), best single discount applies
   * **Velouré Points**: 1 point per $1; 100 points = $5 off
   * **Birthday gift**: free Truffle & Date Gift Box added to an order in the birthday month
7. **Simulated emails** (`email_outbox` table): welcome, order confirmation, cancellation, birthday, new coupon, new flavor. Shown in the staff dashboard.
8. **Staff dashboard**: stats, order status (cancelling restores stock), inventory, create/turn off coupons (emails members), announce new flavors, email outbox.

---

## 4. Project files

```
veloure/
├── docker-compose.yml
├── db/init.sql                    # tables + full menu (generated)
└── web/
    ├── Dockerfile
    ├── requirements.txt           # Flask, psycopg2, Gunicorn, tzdata
    ├── app.py                     # all routes, queries, rules
    ├── templates/                 # HTML pages (Jinja2)
    └── static/
        ├── css/style.css
        └── img/  logo.svg, icon.svg, products/*.jpg (the shop's own photos)
```

---

## 5. Troubleshooting

| Problem | Fix |
|---|---|
| `command not found: docker` | Open Docker Desktop once, then a new Terminal window |
| `Cannot connect to the Docker daemon` | Docker Desktop isn't running; open it and wait for the whale |
| Old products/pages still show | `docker compose down -v` then `docker compose up --build` |
| `port is already allocated` | Change `"8080:5000"` to `"8081:5000"` in `docker-compose.yml` |
| Python/HTML changes don't appear | `docker compose up --build` |
