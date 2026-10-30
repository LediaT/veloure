"""
Velouré Patisserie - Flask web application
==========================================
This file is the "web" container. It:
  * serves the HTML pages (Jinja templates in /templates)
  * talks to the PostgreSQL "db" container with psycopg2
  * keeps the shopping cart in the visitor's session cookie
Payments and emails are SIMULATED: no money moves and no email is really sent.
"""

import os
import re
from datetime import date, datetime, timedelta
from decimal import Decimal
from functools import wraps
from zoneinfo import ZoneInfo

import psycopg2
import psycopg2.extras
from flask import (Flask, abort, flash, g, jsonify, redirect, render_template,
                   request, session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)

# Settings come from environment variables in docker-compose.yml
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "dev-only-secret")
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://veloure:veloure_pass@db:5432/veloure")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "veloure-admin")

# ---------------- Business rules ----------------
SHOP_TZ = ZoneInfo("America/New_York")      # the shop is in Bergen County, NJ
LEAD_HOURS = 24                             # orders need at least 24 hours' notice
MAX_DAYS_AHEAD = 30                         # customers can book up to 30 days ahead
CANCEL_HOURS = 6                            # customers can cancel within 6 hours of ordering
DELIVERY_FEE = Decimal("8.00")
FREE_DELIVERY_MIN = Decimal("55.00")
WELCOME_PERCENT = 10                        # members: 10% off the first order
POINTS_PER_REWARD = 100                     # 100 points ...
REWARD_VALUE = Decimal("5.00")              # ... = $5 off
TIME_SLOTS = [("10:00 AM - 12:00 PM", 10), ("12:00 PM - 2:00 PM", 12),
              ("2:00 PM - 4:00 PM", 14), ("4:00 PM - 6:00 PM", 16)]
PAYMENT_METHODS = ["Visa", "Mastercard", "American Express", "Apple Pay",
                   "Google Pay", "PayPal", "Pay at pickup"]
ORDER_STATUSES = ["received", "in the kitchen", "ready", "completed", "cancelled"]
EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]


def now_nj():
    return datetime.now(SHOP_TZ)


def init_database_if_empty():
    """On a fresh hosted database (e.g. Render) the tables don't exist yet, so load
    init.sql once. Locally, Docker's Postgres already ran init.sql, so this does nothing.
    An advisory lock stops two Gunicorn workers from loading it at the same time."""
    sql_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "init.sql")
    if not os.path.exists(sql_file):
        return
    try:
        conn = psycopg2.connect(DATABASE_URL)
    except psycopg2.Error:
        return
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT pg_advisory_lock(424242)")
            cur.execute("SELECT to_regclass('public.categories')")
            if cur.fetchone()[0] is None:
                with open(sql_file, encoding="utf-8") as f:
                    cur.execute(f.read())
            conn.commit()
            cur.execute("SELECT pg_advisory_unlock(424242)")
    finally:
        conn.close()


init_database_if_empty()


# ------------------------------------------------------------------
# Database helpers
# ------------------------------------------------------------------
def get_db():
    """One connection per request. 'db' in DATABASE_URL is the database
    container's name; Docker's internal DNS turns it into an IP address."""
    if "db" not in g:
        g.db = psycopg2.connect(DATABASE_URL)
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def query(sql, params=(), one=False):
    """Run a SELECT and return rows as dictionaries (values passed separately
    from the SQL text, which protects against SQL injection)."""
    with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return (rows[0] if rows else None) if one else rows


def execute(sql, params=()):
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute(sql, params)
    conn.commit()


def queue_email(to_email, subject, body, kind):
    """SIMULATED email: saved to the email_outbox table instead of being sent.
    A real store would hand this to an email service (SendGrid, Amazon SES...)."""
    execute("INSERT INTO email_outbox (to_email, subject, body, kind) VALUES (%s, %s, %s, %s)",
            (to_email, subject, body, kind))


# ------------------------------------------------------------------
# Logged-in member, template helpers
# ------------------------------------------------------------------
@app.before_request
def load_user():
    g.user = None
    if session.get("user_id"):
        g.user = query("SELECT * FROM users WHERE id = %s", (session["user_id"],), one=True)
        if g.user is None:
            session.pop("user_id", None)


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if g.user is None:
            flash("Please sign in to your Velouré Family account.", "error")
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)
    return wrapper


@app.context_processor
def inject_globals():
    cart = session.get("cart", {})
    return {
        "cart_count": sum(cart.values()),
        "nav_categories": query("SELECT slug, name FROM categories ORDER BY sort_order"),
        "is_admin": session.get("is_admin", False),
        "user": g.get("user"),
        "current_year": date.today().year,
        "payment_methods": PAYMENT_METHODS,
        "free_min": FREE_DELIVERY_MIN,
        "delivery_fee": DELIVERY_FEE,
    }


@app.template_filter("money")
def money(value):
    return f"${Decimal(value):,.2f}"


@app.template_filter("nj")
def nj_time(value, fmt="%b %d, %Y at %-I:%M %p"):
    """Show a stored timestamp in New Jersey time."""
    return value.astimezone(SHOP_TZ).strftime(fmt) if value else ""


# ------------------------------------------------------------------
# Customer pages
# ------------------------------------------------------------------
PRODUCT_LIST_SQL = """
    SELECT p.*, c.name AS category_name, c.slug AS category_slug,
           MIN(v.price) AS from_price, COUNT(v.id) AS variant_count, MIN(v.id) AS first_variant_id
    FROM products p
    JOIN categories c ON c.id = p.category_id
    JOIN product_variants v ON v.product_id = p.id
"""


@app.route("/")
def home():
    best_sellers = query(PRODUCT_LIST_SQL + " WHERE p.is_best_seller AND p.stock > 0 "
                         "GROUP BY p.id, c.id ORDER BY c.sort_order, p.name LIMIT 8")
    categories = query("""
        SELECT c.*, COUNT(p.id) AS product_count,
               (SELECT image_url FROM products WHERE category_id = c.id
                ORDER BY is_best_seller DESC, id LIMIT 1) AS image_url
        FROM categories c LEFT JOIN products p ON p.category_id = c.id
        GROUP BY c.id ORDER BY c.sort_order""")
    return render_template("index.html", best_sellers=best_sellers, categories=categories)


@app.route("/shop")
def shop():
    """Catalog with search, category, dietary filters and sorting.
    The WHERE clause is built from whichever filters the visitor ticked."""
    q = request.args.get("q", "").strip()
    category = request.args.get("category", "")
    filters = {
        "nut_free": "p.is_nut_free",
        "caffeine_free": "NOT p.contains_caffeine",
        "seasonal": "p.is_seasonal",
        "best_seller": "p.is_best_seller",
    }
    sorts = {
        "featured": "c.sort_order, p.is_best_seller DESC, p.name",
        "price_asc": "MIN(v.price), p.name",
        "price_desc": "MIN(v.price) DESC, p.name",
        "name": "p.name",
    }
    sort = request.args.get("sort", "featured")
    sort = sort if sort in sorts else "featured"

    where, params = [], []
    if q:
        where.append("(p.name ILIKE %s OR p.description ILIKE %s OR c.name ILIKE %s)")
        params += [f"%{q}%"] * 3
    if category:
        where.append("c.slug = %s")
        params.append(category)
    active = [k for k in filters if request.args.get(k)]
    where += [filters[k] for k in active]

    sql = PRODUCT_LIST_SQL
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " GROUP BY p.id, c.id ORDER BY " + sorts[sort]
    products = query(sql, params)
    current = query("SELECT * FROM categories WHERE slug = %s", (category,), one=True) if category else None
    return render_template("shop.html", products=products, q=q, category=category,
                           current_category=current, active=active, sort=sort)


@app.route("/product/<slug>")
def product(slug):
    p = query("""SELECT p.*, c.name AS category_name, c.slug AS category_slug
                 FROM products p JOIN categories c ON c.id = p.category_id
                 WHERE p.slug = %s""", (slug,), one=True)
    if p is None:
        abort(404)
    variants = query("SELECT * FROM product_variants WHERE product_id = %s ORDER BY sort_order", (p["id"],))
    related = query(PRODUCT_LIST_SQL + " WHERE p.category_id = %s AND p.id <> %s AND p.image_url <> %s "
                    "GROUP BY p.id, c.id ORDER BY p.is_best_seller DESC, p.name LIMIT 4",
                    (p["category_id"], p["id"], p["image_url"] or ""))
    return render_template("product.html", p=p, variants=variants, related=related)


@app.route("/about")
def about():
    return render_template("about.html")


# ------------------------------------------------------------------
# Cart: session["cart"] = {variant_id: quantity}
# ------------------------------------------------------------------
def get_cart():
    return session.setdefault("cart", {})


def cart_details():
    cart = get_cart()
    if not cart:
        return [], Decimal("0.00")
    rows = query("""SELECT v.id AS variant_id, v.label, v.price, p.*
                    FROM product_variants v JOIN products p ON p.id = v.product_id
                    WHERE v.id = ANY(%s)""", ([int(k) for k in cart],))
    items, subtotal = [], Decimal("0.00")
    for r in rows:
        qty = cart[str(r["variant_id"])]
        line = r["price"] * qty
        subtotal += line
        items.append({"product": r, "variant_id": r["variant_id"], "label": r["label"],
                      "price": r["price"], "qty": qty, "line_total": line})
    # drop anything that no longer exists in the database
    for k in list(cart):
        if int(k) not in {r["variant_id"] for r in rows}:
            cart.pop(k)
    items.sort(key=lambda i: (i["product"]["name"], i["label"]))
    return items, subtotal


def qty_in_cart_for_product(product_id, skip_variant=None):
    """Stock is counted per product, so Medium + Large of the same cake share it."""
    cart = get_cart()
    ids = query("SELECT id FROM product_variants WHERE product_id = %s", (product_id,))
    return sum(cart.get(str(r["id"]), 0) for r in ids if r["id"] != skip_variant)


@app.route("/cart")
def cart():
    items, subtotal = cart_details()
    return render_template("cart.html", items=items, subtotal=subtotal,
                           needed_for_free=max(FREE_DELIVERY_MIN - subtotal, Decimal("0")))


@app.route("/cart/add", methods=["POST"])
def cart_add():
    variant_id = request.form.get("variant_id", type=int)
    qty = max(request.form.get("qty", 1, type=int) or 1, 1)
    v = query("""SELECT v.id, v.label, p.id AS product_id, p.name, p.stock
                 FROM product_variants v JOIN products p ON p.id = v.product_id
                 WHERE v.id = %s""", (variant_id,), one=True)
    if v is None:
        abort(404)
    cart = get_cart()
    current = cart.get(str(v["id"]), 0)
    others = qty_in_cart_for_product(v["product_id"], skip_variant=v["id"])
    available = v["stock"] - others
    if v["stock"] == 0:
        flash(f"Sorry, {v['name']} is fully booked for now.", "error")
    elif current + qty > available:
        cart[str(v["id"])] = max(available, 0)
        if not cart[str(v["id"])]:
            cart.pop(str(v["id"]))
        flash(f"We can take only {v['stock']} orders of {v['name']} right now. Your cart has been updated.", "error")
    else:
        cart[str(v["id"])] = current + qty
        flash(f"{v['name']} ({v['label']}) added to your cart.", "success")
    session.modified = True
    return redirect(request.referrer or url_for("cart"))


@app.route("/cart/update", methods=["POST"])
def cart_update():
    variant_id = request.form.get("variant_id", type=int)
    qty = request.form.get("qty", 0, type=int) or 0
    cart = get_cart()
    v = query("""SELECT p.id AS product_id, p.stock FROM product_variants v
                 JOIN products p ON p.id = v.product_id WHERE v.id = %s""", (variant_id,), one=True)
    if v is None or qty <= 0:
        cart.pop(str(variant_id), None)
    else:
        available = v["stock"] - qty_in_cart_for_product(v["product_id"], skip_variant=variant_id)
        cart[str(variant_id)] = min(qty, max(available, 0))
        if qty > available:
            flash(f"Only {max(available, 0)} available right now.", "error")
        if cart[str(variant_id)] == 0:
            cart.pop(str(variant_id))
    session.modified = True
    return redirect(url_for("cart"))


@app.route("/cart/remove", methods=["POST"])
def cart_remove():
    get_cart().pop(str(request.form.get("variant_id", type=int)), None)
    session.modified = True
    return redirect(url_for("cart"))


# ------------------------------------------------------------------
# Pricing: discounts, points, delivery
# ------------------------------------------------------------------
def is_first_order(user):
    row = query("SELECT COUNT(*) AS n FROM orders WHERE user_id = %s AND status <> 'cancelled'",
                (user["id"],), one=True)
    return row["n"] == 0


def birthday_gift_due(user):
    today = now_nj().date()
    return bool(user and user["birth_month"] == today.month and user["birthday_gift_year"] != today.year)


def price_order(subtotal, user, coupon_code, use_points, fulfillment):
    """Work out every line of the order summary. Used for the preview AND the real order."""
    r = {"subtotal": subtotal, "discount": Decimal("0.00"), "discount_label": None, "coupon": None,
         "coupon_error": None, "points_used": 0, "points_value": Decimal("0.00"),
         "birthday_gift": False, "welcome": False}
    coupon_code = (coupon_code or "").strip().upper()
    if user:
        options = []  # (percent, label) - the best single discount is applied, they do not stack
        if is_first_order(user):
            options.append((WELCOME_PERCENT, "Welcome to the Velouré Family"))
            r["welcome"] = True
        if coupon_code:
            c = query("""SELECT * FROM coupons WHERE UPPER(code) = %s AND is_active
                         AND (ends_on IS NULL OR ends_on >= %s)""", (coupon_code, now_nj().date()), one=True)
            if c:
                options.append((c["percent_off"], f"Coupon {c['code']}"))
                r["coupon"] = c["code"]
            else:
                r["coupon_error"] = "That coupon code is not valid or has expired."
        if options:
            pct, label = max(options)
            r["discount"] = (subtotal * pct / 100).quantize(Decimal("0.01"))
            r["discount_label"] = f"{label} ({pct}% off)"
        if use_points:
            blocks = min(user["points"] // POINTS_PER_REWARD,
                         int((subtotal - r["discount"]) // REWARD_VALUE))
            r["points_used"] = blocks * POINTS_PER_REWARD
            r["points_value"] = REWARD_VALUE * blocks
        r["birthday_gift"] = birthday_gift_due(user)
    elif coupon_code:
        r["coupon_error"] = "Coupons are a Velouré Family benefit. Sign in or join to use one."
    free = fulfillment != "delivery" or subtotal >= FREE_DELIVERY_MIN
    r["fee"] = Decimal("0.00") if free else DELIVERY_FEE
    r["total"] = subtotal - r["discount"] - r["points_value"] + r["fee"]
    r["points_earned"] = int(subtotal - r["discount"] - r["points_value"]) if user else 0
    return r


def earliest_slot():
    """First time slot that is at least 24 hours away (shown to the customer)."""
    limit = now_nj() + timedelta(hours=LEAD_HOURS)
    d = limit.date()
    for _ in range(3):
        for label, hour in TIME_SLOTS:
            if datetime(d.year, d.month, d.day, hour, tzinfo=SHOP_TZ) >= limit:
                return d, label
        d += timedelta(days=1)
    return d, TIME_SLOTS[0][0]


# ------------------------------------------------------------------
# Checkout (simulated payment)
# ------------------------------------------------------------------
@app.route("/checkout", methods=["GET", "POST"])
def checkout():
    items, subtotal = cart_details()
    if not items:
        flash("Your cart is empty.", "error")
        return redirect(url_for("shop"))

    user = g.user
    form = request.form if request.method == "POST" else {}
    errors = []
    fulfillment = form.get("fulfillment", "pickup")
    pricing = price_order(subtotal, user, form.get("coupon"), form.get("use_points"), fulfillment)
    first_date, first_slot = earliest_slot()
    max_date = now_nj().date() + timedelta(days=MAX_DAYS_AHEAD)

    if request.method == "POST" and form.get("action") == "place":
        name = form.get("name", "").strip()
        email = form.get("email", "").strip()
        phone = form.get("phone", "").strip()
        slot = form.get("time_slot", "")
        payment = form.get("payment_method", "")
        street, town, zip_code = (form.get(k, "").strip() for k in ("street", "town", "zip"))
        notes = form.get("notes", "").strip()[:500]

        if not name:
            errors.append("Please enter your name.")
        if not EMAIL_RE.fullmatch(email):
            errors.append("Please enter a valid email address.")
        if fulfillment not in ("pickup", "delivery"):
            errors.append("Please choose pickup or delivery.")
        if payment not in PAYMENT_METHODS:
            errors.append("Please choose a payment method.")
        if pricing["coupon_error"]:
            errors.append(pricing["coupon_error"])
        slot_hours = dict(TIME_SLOTS)
        try:
            requested = date.fromisoformat(form.get("requested_date", ""))
        except ValueError:
            requested = None
            errors.append("Please choose a date.")
        if requested and slot not in slot_hours:
            errors.append("Please choose a time slot.")
        elif requested:
            # 24-hour rule: the chosen slot must start at least 24 hours from now
            start = datetime(requested.year, requested.month, requested.day, slot_hours[slot], tzinfo=SHOP_TZ)
            if start < now_nj() + timedelta(hours=LEAD_HOURS):
                errors.append("Please choose a time at least 24 hours from now so we can prepare your order fresh. "
                              f"The earliest available is {first_date.strftime('%A, %B %d')}, {first_slot}.")
            elif requested > max_date:
                errors.append(f"You can order up to {MAX_DAYS_AHEAD} days ahead.")
        if fulfillment == "delivery":
            if not street or not town:
                errors.append("Please enter your delivery street and town.")
            if not re.fullmatch(r"07\d{3}", zip_code):
                errors.append("We deliver within Bergen County, NJ (ZIP codes starting with 07).")

        if not errors:
            order_number = place_order(items, pricing, user, name, email, phone, fulfillment, requested, slot,
                                       street, town, zip_code, notes, payment, errors)
            if order_number:
                session["cart"] = {}
                session.setdefault("my_orders", []).append(order_number)
                session.modified = True
                return redirect(url_for("confirmation", order_number=order_number))

    if request.method == "POST" and form.get("action") == "apply" and pricing["coupon"]:
        flash(f"Coupon {pricing['coupon']} applied.", "success")
    return render_template("checkout.html", items=items, pricing=pricing, form=form, errors=errors,
                           time_slots=[s for s, _ in TIME_SLOTS], fulfillment=fulfillment,
                           min_date=first_date.isoformat(), max_date=max_date.isoformat(),
                           first_date=first_date, first_slot=first_slot,
                           reward_blocks=(user["points"] // POINTS_PER_REWARD) if user else 0)


def place_order(items, pricing, user, name, email, phone, fulfillment, requested, slot,
                street, town, zip_code, notes, payment, errors):
    """Save the order in ONE transaction: lock stock, insert order + items, lower stock,
    update points. Everything is committed together or rolled back together."""
    conn = get_db()
    is_delivery = fulfillment == "delivery"
    try:
        with conn.cursor() as cur:
            needed = {}
            for it in items:
                needed[it["product"]["id"]] = needed.get(it["product"]["id"], 0) + it["qty"]
            for pid, qty in needed.items():
                # FOR UPDATE locks the row so two customers can't take the last cake at once
                cur.execute("SELECT stock, name FROM products WHERE id = %s FOR UPDATE", (pid,))
                stock, pname = cur.fetchone()
                if stock < qty:
                    raise ValueError(f"Sorry, we can take only {stock} more orders of {pname}. Please update your cart.")
            cur.execute("""
                INSERT INTO orders (user_id, customer_name, email, phone, fulfillment, requested_date, time_slot,
                    street, town, zip, notes, payment_method, subtotal, discount, discount_label,
                    points_used, points_value, points_earned, delivery_fee, total, birthday_gift)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                (user["id"] if user else None, name, email, phone, fulfillment, requested, slot,
                 street if is_delivery else None, town if is_delivery else None, zip_code if is_delivery else None,
                 notes, payment, pricing["subtotal"], pricing["discount"], pricing["discount_label"],
                 pricing["points_used"], pricing["points_value"], pricing["points_earned"],
                 pricing["fee"], pricing["total"], pricing["birthday_gift"]))
            order_id = cur.fetchone()[0]
            order_number = f"VL-{10000 + order_id}"
            cur.execute("UPDATE orders SET order_number = %s WHERE id = %s", (order_number, order_id))
            for it in items:
                cur.execute("""INSERT INTO order_items (order_id, product_id, variant_id, product_name,
                                   variant_label, unit_price, quantity) VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                            (order_id, it["product"]["id"], it["variant_id"], it["product"]["name"],
                             it["label"], it["price"], it["qty"]))
            for pid, qty in needed.items():
                cur.execute("UPDATE products SET stock = stock - %s WHERE id = %s", (qty, pid))
            if pricing["birthday_gift"]:
                cur.execute("""INSERT INTO order_items (order_id, product_id, variant_id, product_name,
                                   variant_label, unit_price, quantity, is_gift)
                               SELECT %s, p.id, v.id, p.name, 'Birthday surprise (complimentary)', 0, 1, TRUE
                               FROM products p JOIN product_variants v ON v.product_id = p.id
                               WHERE p.slug = 'truffle-date-gift-box' LIMIT 1""", (order_id,))
                cur.execute("UPDATE users SET birthday_gift_year = %s WHERE id = %s",
                            (now_nj().year, user["id"]))
            if user:
                cur.execute("UPDATE users SET points = points - %s + %s WHERE id = %s",
                            (pricing["points_used"], pricing["points_earned"], user["id"]))
        conn.commit()
    except ValueError as e:
        conn.rollback()
        errors.append(str(e))
        return None

    deadline = now_nj() + timedelta(hours=CANCEL_HOURS)
    queue_email(email, f"Your Velouré order {order_number} is confirmed",
                f"Hi {name.split(' ')[0]},\n\nThank you for your order! It will be freshly prepared for "
                f"{fulfillment} on {requested.strftime('%A, %B %d')}, {slot}.\nTotal: {money(pricing['total'])} "
                f"(payment: {payment}).\n\nChanged your mind? You can cancel until "
                f"{deadline.strftime('%B %d at %-I:%M %p')}.\n\nVelouré Patisserie, Sweet by nature.",
                "order confirmation")
    return order_number


def can_view_order(order):
    return (order["order_number"] in session.get("my_orders", [])
            or (g.user and order["user_id"] == g.user["id"])
            or session.get("is_admin"))


def cancel_deadline(order):
    return order["created_at"] + timedelta(hours=CANCEL_HOURS)


def cancel_order(order, by_staff=False):
    """Cancel an order: give the stock back, undo points, reset the birthday gift."""
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""UPDATE products p SET stock = p.stock + oi.quantity
                       FROM order_items oi WHERE oi.order_id = %s AND oi.product_id = p.id AND NOT oi.is_gift""",
                    (order["id"],))
        cur.execute("UPDATE orders SET status = 'cancelled', cancelled_at = NOW() WHERE id = %s", (order["id"],))
        if order["user_id"]:
            cur.execute("UPDATE users SET points = GREATEST(points + %s - %s, 0) WHERE id = %s",
                        (order["points_used"], order["points_earned"], order["user_id"]))
            if order["birthday_gift"]:
                cur.execute("UPDATE users SET birthday_gift_year = NULL WHERE id = %s", (order["user_id"],))
    conn.commit()
    queue_email(order["email"], f"Your Velouré order {order['order_number']} has been cancelled",
                f"Hi {order['customer_name'].split(' ')[0]},\n\nYour order {order['order_number']} has been "
                f"cancelled{' by our team' if by_staff else ''}. No charge was made.\n\nWe hope to bake for you "
                "soon.\nVelouré Patisserie", "order cancelled")


@app.route("/order/<order_number>")
def confirmation(order_number):
    order = query("SELECT * FROM orders WHERE order_number = %s", (order_number,), one=True)
    if order is None or not can_view_order(order):
        abort(404)
    items = query("SELECT * FROM order_items WHERE order_id = %s ORDER BY is_gift, product_name", (order["id"],))
    deadline = cancel_deadline(order)
    can_cancel = order["status"] not in ("cancelled", "completed") and datetime.now(SHOP_TZ) < deadline
    return render_template("confirmation.html", order=order, items=items, deadline=deadline,
                           can_cancel=can_cancel)


@app.route("/order/<order_number>/cancel", methods=["POST"])
def cancel(order_number):
    order = query("SELECT * FROM orders WHERE order_number = %s", (order_number,), one=True)
    if order is None or not can_view_order(order):
        abort(404)
    if order["status"] == "cancelled":
        flash("This order was already cancelled.", "error")
    elif order["status"] == "completed" or datetime.now(SHOP_TZ) >= cancel_deadline(order):
        flash("This order can no longer be cancelled because preparation has begun.", "error")
    else:
        cancel_order(order)
        flash("Your order has been cancelled. No charge was made.", "success")
    return redirect(url_for("confirmation", order_number=order_number))


@app.route("/manage-order", methods=["GET", "POST"])
def manage_order():
    if request.method == "POST":
        number = request.form.get("order_number", "").strip().upper()
        email = request.form.get("email", "").strip().lower()
        order = query("SELECT order_number FROM orders WHERE UPPER(order_number) = %s AND LOWER(email) = %s",
                      (number, email), one=True)
        if order:
            session.setdefault("my_orders", []).append(order["order_number"])
            session.modified = True
            return redirect(url_for("confirmation", order_number=order["order_number"]))
        flash("We couldn't find an order with that number and email.", "error")
    return render_template("manage_order.html")


# ------------------------------------------------------------------
# Velouré Family: accounts
# ------------------------------------------------------------------
def maybe_send_birthday_email(user):
    today = now_nj().date()
    if user and user["birth_month"] == today.month and user["birthday_email_year"] != today.year:
        queue_email(user["email"], "Happy birthday from Velouré!",
                    f"Happy birthday, {user['name'].split(' ')[0]}!\n\nYour surprise Truffle & Date Gift Box is "
                    "waiting for you. It will be added free to your next order this month.\n\nWith love,\nVelouré",
                    "birthday")
        execute("UPDATE users SET birthday_email_year = %s WHERE id = %s", (today.year, user["id"]))


def safe_next(default):
    nxt = request.args.get("next", "")
    return nxt if nxt.startswith("/") and not nxt.startswith("//") else default


@app.route("/join", methods=["GET", "POST"])
def register():
    form = request.form if request.method == "POST" else {"email": request.args.get("email", "")}
    errors = []
    if request.method == "POST":
        name = form.get("name", "").strip()
        email = form.get("email", "").strip().lower()
        password = form.get("password", "")
        month = form.get("birth_month", type=int)
        day = form.get("birth_day", type=int)
        if not name:
            errors.append("Please enter your name.")
        if not EMAIL_RE.fullmatch(email):
            errors.append("Please enter a valid email address.")
        if len(password) < 8:
            errors.append("Your password needs at least 8 characters.")
        if not month or not day:
            errors.append("Please tell us your birthday so we can surprise you.")
        if not errors and query("SELECT 1 FROM users WHERE email = %s", (email,), one=True):
            errors.append("That email already has an account. Please sign in.")
        if not errors:
            with get_db().cursor() as cur:
                cur.execute("""INSERT INTO users (name, email, password_hash, birth_month, birth_day)
                               VALUES (%s, %s, %s, %s, %s) RETURNING id""",
                            (name, email, generate_password_hash(password), month, day))
                user_id = cur.fetchone()[0]
            get_db().commit()
            queue_email(email, "Welcome to the Velouré Family",
                        f"Hi {name.split(' ')[0]},\n\nWelcome to the Velouré Family! Enjoy 10% off your first order, "
                        "exclusive coupons, Velouré Points on every purchase (100 points = $5 off), and a surprise "
                        "gift box on your birthday.\n\nSweet by nature,\nVelouré Patisserie", "welcome")
            session["user_id"] = user_id
            g.user = query("SELECT * FROM users WHERE id = %s", (user_id,), one=True)
            maybe_send_birthday_email(g.user)
            flash("Welcome to the Velouré Family! 10% off your first order is ready at checkout.", "success")
            return redirect(safe_next(url_for("account")))
    return render_template("register.html", form=form, errors=errors, months=MONTHS)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        user = query("SELECT * FROM users WHERE email = %s", (email,), one=True)
        if user and check_password_hash(user["password_hash"], request.form.get("password", "")):
            session["user_id"] = user["id"]
            maybe_send_birthday_email(user)
            flash(f"Welcome back, {user['name'].split(' ')[0]}.", "success")
            return redirect(safe_next(url_for("account")))
        flash("Incorrect email or password.", "error")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.pop("user_id", None)
    flash("You have been signed out.", "success")
    return redirect(url_for("home"))


@app.route("/account")
@login_required
def account():
    user = g.user
    maybe_send_birthday_email(user)
    orders = query("""SELECT o.*, (SELECT SUM(quantity) FROM order_items WHERE order_id = o.id) AS item_count
                      FROM orders o WHERE user_id = %s ORDER BY created_at DESC""", (user["id"],))
    coupons = query("SELECT * FROM coupons WHERE is_active AND (ends_on IS NULL OR ends_on >= %s) ORDER BY created_at DESC",
                    (now_nj().date(),))
    return render_template("account.html", orders=orders, coupons=coupons,
                           first_order=is_first_order(user), birthday_due=birthday_gift_due(user),
                           birth_month_name=MONTHS[user["birth_month"] - 1] if user["birth_month"] else "",
                           rewards=user["points"] // POINTS_PER_REWARD,
                           to_next=POINTS_PER_REWARD - user["points"] % POINTS_PER_REWARD)


# ------------------------------------------------------------------
# Staff dashboard (password protected)
# ------------------------------------------------------------------
def admin_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not session.get("is_admin"):
            return redirect(url_for("admin_login", next=request.path))
        return view(*args, **kwargs)
    return wrapper


@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    if request.method == "POST":
        if request.form.get("password") == ADMIN_PASSWORD:
            session["is_admin"] = True
            flash("Welcome to the kitchen dashboard.", "success")
            nxt = request.args.get("next", "")
            return redirect(nxt if nxt.startswith("/admin") else url_for("admin_dashboard"))
        flash("Incorrect password.", "error")
    return render_template("admin/login.html")


@app.route("/admin/logout")
def admin_logout():
    session.pop("is_admin", None)
    flash("You have been logged out of the dashboard.", "success")
    return redirect(url_for("home"))


@app.route("/admin")
@admin_required
def admin_dashboard():
    stats = query("""SELECT COUNT(*) FILTER (WHERE status <> 'cancelled') AS orders,
                            COALESCE(SUM(total) FILTER (WHERE status <> 'cancelled'), 0) AS revenue,
                            COUNT(*) FILTER (WHERE status NOT IN ('completed', 'cancelled')) AS open_orders,
                            COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled
                     FROM orders""", one=True)
    members = query("SELECT COUNT(*) AS n FROM users", one=True)["n"]
    low_stock = query("SELECT COUNT(*) AS n FROM products WHERE stock <= 3", one=True)["n"]
    orders = query("""SELECT o.*, (SELECT SUM(quantity) FROM order_items WHERE order_id = o.id) AS item_count
                      FROM orders o ORDER BY o.created_at DESC LIMIT 25""")
    products = query("""SELECT p.id, p.name, p.slug, p.stock, c.name AS category_name, MIN(v.price) AS from_price
                        FROM products p JOIN categories c ON c.id = p.category_id
                        JOIN product_variants v ON v.product_id = p.id
                        GROUP BY p.id, c.name ORDER BY p.stock, p.name""")
    top = query("""SELECT product_name, SUM(oi.quantity) AS sold FROM order_items oi
                   JOIN orders o ON o.id = oi.order_id
                   WHERE o.status <> 'cancelled' AND NOT oi.is_gift
                   GROUP BY product_name ORDER BY sold DESC LIMIT 5""")
    coupons = query("SELECT * FROM coupons ORDER BY created_at DESC")
    outbox = query("SELECT * FROM email_outbox ORDER BY created_at DESC LIMIT 30")
    return render_template("admin/dashboard.html", stats=stats, members=members, low_stock=low_stock,
                           orders=orders, products=products, top=top, coupons=coupons, outbox=outbox,
                           statuses=ORDER_STATUSES)


@app.route("/admin/product/<int:product_id>/stock", methods=["POST"])
@admin_required
def admin_update_stock(product_id):
    stock = request.form.get("stock", type=int)
    if stock is None or stock < 0:
        flash("Stock must be zero or more.", "error")
    else:
        execute("UPDATE products SET stock = %s WHERE id = %s", (stock, product_id))
        flash("Stock updated.", "success")
    return redirect(url_for("admin_dashboard") + "#inventory")


@app.route("/admin/order/<int:order_id>/status", methods=["POST"])
@admin_required
def admin_update_status(order_id):
    status = request.form.get("status")
    order = query("SELECT * FROM orders WHERE id = %s", (order_id,), one=True)
    if order and status in ORDER_STATUSES and status != order["status"]:
        if order["status"] == "cancelled":
            flash("A cancelled order cannot be reopened. Please ask the customer to order again.", "error")
        elif status == "cancelled":
            cancel_order(order, by_staff=True)
            flash("Order cancelled. Stock and points were restored.", "success")
        else:
            execute("UPDATE orders SET status = %s WHERE id = %s", (status, order_id))
            flash("Order status updated.", "success")
    return redirect(url_for("admin_dashboard") + "#orders")


def email_all_members(subject, body, kind):
    for m in query("SELECT name, email FROM users"):
        queue_email(m["email"], subject, f"Hi {m['name'].split(' ')[0]},\n\n{body}\n\nSweet by nature,\nVelouré", kind)


@app.route("/admin/coupons", methods=["POST"])
@admin_required
def admin_create_coupon():
    code = request.form.get("code", "").strip().upper()
    pct = request.form.get("percent_off", type=int)
    desc = request.form.get("description", "").strip()[:200]
    ends = request.form.get("ends_on") or None
    if not re.fullmatch(r"[A-Z0-9]{3,30}", code) or not pct or not 1 <= pct <= 50:
        flash("Use a code of 3-30 letters/numbers and a discount between 1% and 50%.", "error")
    elif query("SELECT 1 FROM coupons WHERE code = %s", (code,), one=True):
        flash("That coupon code already exists.", "error")
    else:
        execute("INSERT INTO coupons (code, percent_off, description, ends_on) VALUES (%s, %s, %s, %s)",
                (code, pct, desc, ends))
        email_all_members(f"A new coupon for you: {pct}% off",
                          f"{desc or 'A little treat from us.'} Use code {code} at checkout"
                          f"{' until ' + ends if ends else ''}.", "new coupon")
        flash(f"Coupon {code} created and emailed to all members.", "success")
    return redirect(url_for("admin_dashboard") + "#coupons")


@app.route("/admin/coupons/<int:coupon_id>/toggle", methods=["POST"])
@admin_required
def admin_toggle_coupon(coupon_id):
    execute("UPDATE coupons SET is_active = NOT is_active WHERE id = %s", (coupon_id,))
    return redirect(url_for("admin_dashboard") + "#coupons")


@app.route("/admin/announce", methods=["POST"])
@admin_required
def admin_announce():
    p = query("SELECT name, slug FROM products WHERE id = %s", (request.form.get("product_id", type=int),), one=True)
    if p:
        email_all_members(f"New at Velouré: {p['name']}",
                          f"We've just introduced something new: {p['name']}. Come taste it, fresh from our kitchen.",
                          "new flavor")
        flash(f"Announcement for {p['name']} emailed to all members.", "success")
    return redirect(url_for("admin_dashboard") + "#outbox")


# ------------------------------------------------------------------
# Health check - proves the web container can reach the db container
# ------------------------------------------------------------------
@app.route("/health")
def health():
    try:
        row = query("SELECT COUNT(*) AS products FROM products", one=True)
        return jsonify(status="ok", web="running", database="connected", products=row["products"])
    except psycopg2.Error as e:
        return jsonify(status="error", web="running", database="unreachable", detail=str(e)), 500


@app.errorhandler(404)
def not_found(_e):
    return render_template("404.html"), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
