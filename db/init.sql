-- =============================================================
-- Velouré Patisserie - database setup (generated menu, do not edit by hand
-- unless you know what you are doing)
-- PostgreSQL runs this file automatically the FIRST time the "db" container
-- starts. To load it again from scratch:
--     docker compose down -v
--     docker compose up --build
-- =============================================================

-- Product groups (Signature Cakes, Cookies, ...)
CREATE TABLE categories (
    id          SERIAL PRIMARY KEY,
    slug        VARCHAR(50)  UNIQUE NOT NULL,
    name        VARCHAR(100) NOT NULL,
    blurb       VARCHAR(200),
    sort_order  INT NOT NULL DEFAULT 0
);

-- Every item on the menu
CREATE TABLE products (
    id                SERIAL PRIMARY KEY,
    category_id       INT NOT NULL REFERENCES categories(id),
    slug              VARCHAR(100) UNIQUE NOT NULL,
    name              VARCHAR(150) NOT NULL,
    description       TEXT NOT NULL,
    tagline           VARCHAR(200) NOT NULL DEFAULT '',
    allergens         VARCHAR(200) NOT NULL DEFAULT '',
    image_url         TEXT,
    image2_url        TEXT,                                   -- optional second photo
    stock             INT NOT NULL DEFAULT 0 CHECK (stock >= 0),   -- orders we can still take
    is_nut_free       BOOLEAN NOT NULL DEFAULT FALSE,
    contains_caffeine BOOLEAN NOT NULL DEFAULT FALSE,
    is_seasonal       BOOLEAN NOT NULL DEFAULT FALSE,
    is_best_seller    BOOLEAN NOT NULL DEFAULT FALSE
);

-- Sizes / options with their own price (Medium vs Large, 1 piece vs Box of 6 ...)
CREATE TABLE product_variants (
    id          SERIAL PRIMARY KEY,
    product_id  INT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    label       VARCHAR(60) NOT NULL,
    price       NUMERIC(8,2) NOT NULL CHECK (price >= 0),
    sort_order  INT NOT NULL DEFAULT 0
);

-- Velouré Family members (customer accounts)
CREATE TABLE users (
    id                    SERIAL PRIMARY KEY,
    name                  VARCHAR(120) NOT NULL,
    email                 VARCHAR(160) UNIQUE NOT NULL,
    password_hash         VARCHAR(255) NOT NULL,      -- never the plain password
    birth_month           INT CHECK (birth_month BETWEEN 1 AND 12),
    birth_day             INT CHECK (birth_day BETWEEN 1 AND 31),
    points                INT NOT NULL DEFAULT 0 CHECK (points >= 0),
    birthday_gift_year    INT,                        -- year the birthday gift was last claimed
    birthday_email_year   INT,                        -- year the birthday email was last sent
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Discount codes for members (created in the staff dashboard)
CREATE TABLE coupons (
    id           SERIAL PRIMARY KEY,
    code         VARCHAR(30) UNIQUE NOT NULL,
    percent_off  INT NOT NULL CHECK (percent_off BETWEEN 1 AND 50),
    description  VARCHAR(200) NOT NULL DEFAULT '',
    ends_on      DATE,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per order (no real payment is collected)
CREATE TABLE orders (
    id               SERIAL PRIMARY KEY,
    order_number     VARCHAR(20) UNIQUE,
    user_id          INT REFERENCES users(id),        -- NULL for guest checkout
    customer_name    VARCHAR(120) NOT NULL,
    email            VARCHAR(160) NOT NULL,
    phone            VARCHAR(40),
    fulfillment      VARCHAR(10) NOT NULL CHECK (fulfillment IN ('pickup', 'delivery')),
    requested_date   DATE NOT NULL,
    time_slot        VARCHAR(30) NOT NULL,
    street           VARCHAR(160),
    town             VARCHAR(80),
    zip              VARCHAR(10),
    notes            TEXT,
    payment_method   VARCHAR(30) NOT NULL,
    subtotal         NUMERIC(10,2) NOT NULL,
    discount         NUMERIC(10,2) NOT NULL DEFAULT 0,
    discount_label   VARCHAR(80),
    points_used      INT NOT NULL DEFAULT 0,
    points_value     NUMERIC(10,2) NOT NULL DEFAULT 0,
    points_earned    INT NOT NULL DEFAULT 0,
    delivery_fee     NUMERIC(10,2) NOT NULL DEFAULT 0,
    total            NUMERIC(10,2) NOT NULL,
    birthday_gift    BOOLEAN NOT NULL DEFAULT FALSE,
    status           VARCHAR(20) NOT NULL DEFAULT 'received'
                     CHECK (status IN ('received', 'in the kitchen', 'ready', 'completed', 'cancelled')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at     TIMESTAMPTZ
);

-- Products inside each order
CREATE TABLE order_items (
    id             SERIAL PRIMARY KEY,
    order_id       INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id     INT NOT NULL REFERENCES products(id),
    variant_id     INT REFERENCES product_variants(id),
    product_name   VARCHAR(150) NOT NULL,     -- copied so old orders keep their names
    variant_label  VARCHAR(60) NOT NULL,
    unit_price     NUMERIC(8,2) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    is_gift        BOOLEAN NOT NULL DEFAULT FALSE
);

-- Simulated emails: saved here instead of really being sent (shown in the staff dashboard)
CREATE TABLE email_outbox (
    id          SERIAL PRIMARY KEY,
    to_email    VARCHAR(160) NOT NULL,
    subject     VARCHAR(200) NOT NULL,
    body        TEXT NOT NULL,
    kind        VARCHAR(30) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_variants_product  ON product_variants(product_id);
CREATE INDEX idx_items_order       ON order_items(order_id);
CREATE INDEX idx_orders_user       ON orders(user_id);


-- ---------- CATEGORIES ----------
INSERT INTO categories (slug, name, blurb, sort_order) VALUES
('signature-cakes', 'Signature Cakes', 'Our showpiece cakes, in Medium (serves 4) or Large (serves 6-8).', 1),
('cheesecakes', 'Cheesecakes', 'Velvety, creamy, and made without dairy or refined sugar.', 2),
('loaf-cakes', 'Loaf & Everyday Cakes', 'Simple, comforting cakes for every day of the week.', 3),
('cupcakes', 'Cupcakes', 'Little celebrations, by the piece or in a box of four.', 4),
('cookies', 'Cookies', 'Baked in small batches, by the piece or by the pack.', 5),
('brownies-bars', 'Brownies & Bars', 'Fudgy brownies and our handmade chocolate bars.', 6),
('truffles-energy-balls', 'Truffles & Energy Balls', 'Hand-rolled bites, by the piece or in a box.', 7),
('stuffed-dates', 'Stuffed Dates', 'Soft dates with homemade fillings, by the piece or in a box.', 8),
('gift-boxes', 'Gift Boxes', 'Give something sweet, the kind that loves them back.', 9);

-- ---------- PRODUCTS (79) AND THEIR SIZES ----------
INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'veloure-cake', 'Velouré Cake',
  'A crunchy gluten-free biscuit base, a silky cream made entirely with our homemade cashew butter, and fresh exotic fruit that gives every bite its own unique flavor.',
  'A cake that isn''t just dessert. It''s an experience.', 'Tree nuts (cashew)', '/static/img/products/veloure-cake.jpg', NULL, 8, FALSE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='veloure-cake'), 'Medium (serves 4)', 38.00, 0), ((SELECT id FROM products WHERE slug='veloure-cake'), 'Large (serves 6-8)', 58.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'caramel-cake', 'Caramel Cake',
  'A crunchy nut base, a smooth vanilla cream, and a thick layer of caramel made with coconut sugar, loaded with roasted nuts.',
  'Rich, golden, and impossible to stop at one slice.', 'Tree nuts (cashew, almond)', '/static/img/products/caramel-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='caramel-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='caramel-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'pecan-caramel-cake', 'Pecan Caramel Cake',
  'A crunchy nut base, a smooth vanilla cream, and a golden caramel made with coconut sugar, poured over roasted pecans so it drips down every side.',
  'Buttery, nutty, and pure comfort in every slice.', 'Tree nuts (pecan, cashew)', '/static/img/products/pecan-caramel-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pecan-caramel-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='pecan-caramel-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'cocoa-peanut-cake', 'Cocoa & Peanut Cake',
  'A crunchy peanut base, a soft vanilla cream, and a swirled top of cocoa butter chocolate finished with chopped peanuts and cacao crumble.',
  'The classic chocolate and peanut pairing, made the natural way.', 'Peanuts, tree nuts (cashew)', '/static/img/products/cocoa-peanut-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='cocoa-peanut-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='cocoa-peanut-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'peanut-butter-cocoa-cake', 'Peanut Butter Cocoa Cake',
  'A golden peanut crust and a rich chocolate cream made with our homemade peanut butter and coconut cream, crowned with roasted peanuts and dark chocolate shards.',
  'For everyone who believes peanut butter and chocolate belong together.', 'Peanuts, coconut', '/static/img/products/peanut-butter-cocoa-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='peanut-butter-cocoa-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='peanut-butter-cocoa-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'cherry-coconut-cake', 'Cherry Coconut Cake',
  'A crunchy nut base and three velvety layers of coconut, wild berry, and cocoa cream, made with our homemade coconut butter and crowned with fresh dark cherries.',
  'Elegant, layered, and as beautiful as it tastes.', 'Tree nuts (cashew), coconut', '/static/img/products/cherry-coconut-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='cherry-coconut-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='cherry-coconut-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'coconut-cake', 'Coconut Cake',
  'A tender coconut base, a sunny orange cream made with our homemade coconut butter, and a soft strawberry layer, topped with fresh berries and orange slices.',
  'The perfect harmony of freshness and elegance.', 'Coconut', '/static/img/products/coconut-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='coconut-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='coconut-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'pistachio-cake', 'Pistachio Cake',
  'A crunchy pistachio base and a silky cream made with our homemade artisanal pistachio butter, topped with fresh raspberries.',
  'Delicate, nutty, and refreshingly light.', 'Tree nuts (pistachio)', '/static/img/products/pistachio-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-cake'), 'Medium (serves 4)', 38.00, 0), ((SELECT id FROM products WHERE slug='pistachio-cake'), 'Large (serves 6-8)', 58.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'pistachio-cocoa-cake', 'Pistachio Cocoa Cake',
  'A moist, vivid green pistachio cake made with our homemade pistachio butter, under a smooth layer of cocoa butter chocolate and a scattering of slivered pistachios.',
  'Bold, elegant, and made for pistachio lovers.', 'Tree nuts (pistachio)', '/static/img/products/pistachio-cocoa-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-cocoa-cake'), 'Medium (serves 4)', 38.00, 0), ((SELECT id FROM products WHERE slug='pistachio-cocoa-cake'), 'Large (serves 6-8)', 58.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'blueberry-cake', 'Blueberry Cake',
  'A crunchy nut base, a smooth vanilla cream, and a deep violet layer of our homemade blueberry jam, crowned with fresh blueberries.',
  'Fresh, fruity, and full of summer.', 'Tree nuts (cashew)', '/static/img/products/blueberry-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='blueberry-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='blueberry-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'wild-blueberry-cocoa-cake', 'Wild Blueberry Cocoa Cake',
  'A date and nut base, a smooth cocoa cream, and a vivid wild blueberry mousse, finished with fresh raspberries and blueberries.',
  'Fruity, chocolatey, and beautifully bold.', 'Tree nuts (cashew, almond)', '/static/img/products/wild-blueberry-cocoa-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='wild-blueberry-cocoa-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='wild-blueberry-cocoa-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'raspberry-cake', 'Raspberry Cake',
  'A crunchy golden base, a smooth vanilla cream, a soft raspberry mousse, and a glossy layer of our homemade raspberry jam, crowned with fresh raspberries.',
  'Bright, elegant, and made for celebrating.', 'Tree nuts (cashew)', '/static/img/products/raspberry-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='raspberry-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='raspberry-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'chocolate-cake', 'Chocolate Cake',
  'A dark cacao base and a silky chocolate mousse made with pure cocoa butter, finished with cacao crumble and a touch of shimmer.',
  'Deep, velvety, and made for true chocolate lovers.', 'Tree nuts (cashew)', '/static/img/products/chocolate-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='chocolate-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='chocolate-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'hazelnut-praline-cake', 'Hazelnut Praline Cake',
  'A silky chocolate hazelnut cream on a crunchy base, finished with a glossy layer of cocoa butter chocolate, toasted hazelnut pieces, and our Hazelnut Crunch Truffles on top.',
  'Rich, nutty, and irresistibly smooth.', 'Tree nuts (hazelnut)', '/static/img/products/hazelnut-praline-cake.jpg', NULL, 3, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='hazelnut-praline-cake'), 'Medium (serves 4)', 38.00, 0), ((SELECT id FROM products WHERE slug='hazelnut-praline-cake'), 'Large (serves 6-8)', 58.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'mocha-obsession', 'Mocha Obsession',
  'A dark cacao base, a silky espresso and chocolate mousse made with pure cocoa butter, and dramatic shards of dark chocolate scattered with coffee beans.',
  'Made for those who take their coffee and their chocolate seriously.', 'Tree nuts (cashew)', '/static/img/products/mocha-obsession.jpg', NULL, 6, FALSE, TRUE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='mocha-obsession'), 'Medium (serves 4)', 38.00, 0), ((SELECT id FROM products WHERE slug='mocha-obsession'), 'Large (serves 6-8)', 58.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'matcha-cake', 'Matcha Cake',
  'A crunchy nut base, a smooth matcha cream made with our homemade coconut butter, and a soft raspberry mousse crowned with fresh raspberries.',
  'Calm, vibrant, and beautifully balanced.', 'Tree nuts (cashew), coconut', '/static/img/products/matcha-cake.jpg', NULL, 0, FALSE, TRUE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='matcha-cake'), 'Medium (serves 4)', 38.00, 0), ((SELECT id FROM products WHERE slug='matcha-cake'), 'Large (serves 6-8)', 58.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'pear-cocoa-cake', 'Pear & Cocoa Cake',
  'A crunchy cacao base, a deep layer of chocolate cream made with cocoa butter, and a spiced pear cream topped with fresh pear slices, cinnamon, and pecans.',
  'Warm, comforting, and wrapped in the flavors of autumn.', 'Tree nuts (pecan, cashew)', '/static/img/products/pear-cocoa-cake.jpg', NULL, 6, FALSE, FALSE, TRUE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pear-cocoa-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='pear-cocoa-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'golden-ginger-cake', 'Golden Ginger Cake',
  'A crunchy nut base and a velvety golden cream warmed with fresh ginger and gentle spices, crowned with pecans and a delicate physalis.',
  'Soft, glowing, and as cozy as an autumn evening.', 'Tree nuts (pecan, cashew)', '/static/img/products/golden-ginger-cake.jpg', NULL, 6, FALSE, FALSE, TRUE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='golden-ginger-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='golden-ginger-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='signature-cakes'), 'almond-cream-cake', 'Almond Cream Cake',
  'Soft layers of cake and silky coconut cream, wrapped in toasted chopped almonds and finished with snowy coconut and a single fresh raspberry.',
  'Light, tender, and timelessly elegant.', 'Tree nuts (almond), coconut', '/static/img/products/almond-cream-cake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='almond-cream-cake'), 'Medium (serves 4)', 34.00, 0), ((SELECT id FROM products WHERE slug='almond-cream-cake'), 'Large (serves 6-8)', 52.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'banana-bliss-cheesecake', 'Banana Bliss Cheesecake',
  'When banana meets hazelnuts, peanuts, dates, apricot, and raspberry, the result is a cheesecake you simply have to try. Creamy and soft, with a blend of flavors perfectly balanced by the natural sweetness of fruit.',
  'One of those desserts you enjoy for pure pleasure, and still feel good about choosing.', 'Tree nuts (hazelnut, cashew), peanuts', '/static/img/products/banana-bliss-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='banana-bliss-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='banana-bliss-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'chocolate-walnut-cheesecake', 'Chocolate Walnut Cheesecake',
  'A dark cacao base, a creamy vanilla cheesecake layer, a smooth chocolate top, and a generous mound of walnuts glazed in date caramel.',
  'Indulgent, crunchy, and impossible to share.', 'Tree nuts (walnut, cashew)', '/static/img/products/chocolate-walnut-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='chocolate-walnut-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='chocolate-walnut-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'carrot-pistachio-cheesecake', 'Carrot Pistachio Cheesecake',
  'A spiced carrot and date base, a silky vanilla cream, and a topping of fresh carrot ribbons, crushed pistachios, and dried cranberries.',
  'Everything you love about carrot cake, in its most elegant form.', 'Tree nuts (pistachio, cashew)', '/static/img/products/carrot-pistachio-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='carrot-pistachio-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='carrot-pistachio-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'lemon-apricot-cheesecake', 'Lemon Apricot Cheesecake',
  'A golden apricot and nut base and a bright lemon cream made with coconut cream, finished with lemon zest, dried orange, and fresh berries.',
  'Sunny, zesty, and wonderfully refreshing.', 'Tree nuts (cashew), coconut', '/static/img/products/lemon-apricot-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='lemon-apricot-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='lemon-apricot-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'raspberry-coconut-cheesecake', 'Raspberry Coconut Cheesecake',
  'A crunchy date and nut base and a vivid pink raspberry cream with whole raspberries inside, framed with snowy coconut.',
  'Light, fruity, and pretty as a picture.', 'Tree nuts (cashew), coconut', '/static/img/products/raspberry-coconut-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='raspberry-coconut-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='raspberry-coconut-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'apple-caramel-crumble-cheesecake', 'Apple Caramel Crumble Cheesecake',
  'A date and nut base and a velvety vanilla cheesecake with dried fruit and apple, topped with a golden crumble, dark chocolate pieces, and a drizzle of date caramel.',
  'Comfort food, dressed up for dessert.', 'Tree nuts (cashew, almond)', '/static/img/products/apple-caramel-crumble-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='apple-caramel-crumble-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='apple-caramel-crumble-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'walnut-almond-apple-cheesecake', 'Walnut Almond Apple Cheesecake',
  'A crunchy nut base, a velvety coconut cream cheesecake layered with spiced apples, and an oat-and-walnut crumble finished with a generous drizzle of date caramel.',
  'Warm, cozy, and everything you love about autumn.', 'Tree nuts (walnut, almond), coconut', '/static/img/products/walnut-almond-apple-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='walnut-almond-apple-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='walnut-almond-apple-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cheesecakes'), 'tahini-sesame-cheesecake', 'Tahini Sesame Cheesecake',
  'A crunchy date and nut base, a velvety cream made with our homemade tahini, a dark chocolate drizzle, and hand-rolled sesame truffles on top.',
  'Nutty, elegant, and quietly unforgettable.', 'Sesame, tree nuts (cashew)', '/static/img/products/tahini-sesame-cheesecake.jpg', NULL, 6, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='tahini-sesame-cheesecake'), 'Medium (serves 4)', 36.00, 0), ((SELECT id FROM products WHERE slug='tahini-sesame-cheesecake'), 'Large (serves 6-8)', 54.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='loaf-cakes'), 'apple-pecan-cake', 'Apple Pecan Cake',
  'A tender almond flour cake baked with fresh apples, toasted pecans, and warm cinnamon, finished with a glossy drizzle of pure maple syrup.',
  'Cozy, golden, and made for slow autumn afternoons.', 'Tree nuts (almond, pecan)', '/static/img/products/apple-pecan-cake.jpg', NULL, 8, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='apple-pecan-cake'), 'Medium (serves 4)', 28.00, 0), ((SELECT id FROM products WHERE slug='apple-pecan-cake'), 'Large (serves 6-8)', 42.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='loaf-cakes'), 'date-walnut-cake', 'Date Walnut Cake',
  'A soft, spiced cake studded with sticky dates and toasted walnuts, baked until golden with a gently caramelized crust.',
  'Simple, nostalgic, and perfect with a cup of tea.', 'Tree nuts (walnut)', '/static/img/products/date-walnut-cake.jpg', NULL, 8, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='date-walnut-cake'), 'Medium (serves 4)', 26.00, 0), ((SELECT id FROM products WHERE slug='date-walnut-cake'), 'Large (serves 6-8)', 38.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='loaf-cakes'), 'veloure-caramel-cloud', 'Velouré Caramel Cloud',
  'A soft, airy sponge soaked in creamy oat milk and crowned with a glossy layer of our homemade date caramel.',
  'Make it today, love it tomorrow.', 'Coconut', '/static/img/products/veloure-caramel-cloud.jpg', NULL, 8, TRUE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='veloure-caramel-cloud'), 'Medium (serves 4)', 24.00, 0), ((SELECT id FROM products WHERE slug='veloure-caramel-cloud'), 'Large (serves 6-8)', 38.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cupcakes'), 'wild-berry-cupcakes', 'Wild Berry Cupcakes',
  'A soft vanilla cupcake crowned with a swirl of berry cream made with our homemade coconut butter and berry jam, dotted with fresh red currants and blueberries.',
  'Light, pretty, and made for every celebration.', 'Coconut', '/static/img/products/wild-berry-cupcakes.jpg', NULL, 40, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='wild-berry-cupcakes'), '1 cupcake', 4.50, 0), ((SELECT id FROM products WHERE slug='wild-berry-cupcakes'), 'Box of 4', 17.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cupcakes'), 'cocoa-peanut-butter-cupcakes', 'Cocoa Peanut Butter Cupcakes',
  'Moist cocoa cupcakes made with almond and coconut flour and our homemade peanut butter, topped with dark chocolate chunks and a crunchy nut crumble.',
  'Rich, fudgy, and deeply satisfying.', 'Tree nuts (almond), peanuts, coconut', '/static/img/products/cocoa-peanut-butter-cupcakes.jpg', NULL, 40, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='cocoa-peanut-butter-cupcakes'), '1 cupcake', 4.75, 0), ((SELECT id FROM products WHERE slug='cocoa-peanut-butter-cupcakes'), 'Box of 4', 18.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'pistachio-raspberry-cookies', 'Pistachio Raspberry Cookies',
  'Golden almond and pistachio cookies with a generous heart of our homemade raspberry jam, finished with crushed pistachios.',
  'Tender, jammy, and perfect with an afternoon coffee.', 'Tree nuts (almond, pistachio)', '/static/img/products/pistachio-raspberry-cookies.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-raspberry-cookies'), '1 cookie', 3.00, 0), ((SELECT id FROM products WHERE slug='pistachio-raspberry-cookies'), 'Pack of 4', 11.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'pistachio-rose-cookies', 'Pistachio Rose Cookies',
  'Rustic cookies packed with pistachios, apricots, raisins, and delicate rose petals, made without refined sugar, gluten, or lactose.',
  'A unique flavor you won''t forget.', 'Tree nuts (pistachio)', '/static/img/products/pistachio-rose-cookies.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-rose-cookies'), '1 cookie', 3.50, 0), ((SELECT id FROM products WHERE slug='pistachio-rose-cookies'), 'Pack of 4', 13.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'oat-heart-sandwich-cookies', 'Oat Heart Sandwich Cookies',
  'Golden gluten-free oat cookies sandwiched with a rich chocolate peanut cream, with a little heart cut out on top.',
  'Made with love, in every sense.', 'Peanuts', '/static/img/products/oat-heart-sandwich-cookies.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='oat-heart-sandwich-cookies'), '1 cookie', 3.25, 0), ((SELECT id FROM products WHERE slug='oat-heart-sandwich-cookies'), 'Pack of 4', 12.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'almond-dark-chocolate-cookies', 'Almond Dark Chocolate Cookies',
  'Buttery almond flour shortbread, half-dipped in dark chocolate made with pure cocoa butter and finished with crunchy chopped almonds.',
  'Crisp, elegant, and perfect with a cup of coffee.', 'Tree nuts (almond)', '/static/img/products/almond-dark-chocolate-cookies.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='almond-dark-chocolate-cookies'), '1 cookie', 3.00, 0), ((SELECT id FROM products WHERE slug='almond-dark-chocolate-cookies'), 'Pack of 6', 16.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'cocoa-coconut-walnut-cookies', 'Cocoa Coconut Walnut Cookies',
  'Chewy cocoa cookies packed with toasted coconut, crunchy walnuts, and chunks of cocoa butter dark chocolate, finished with a pinch of sea salt.',
  'Rich, rustic, and impossible to stop at one.', 'Tree nuts (walnut), coconut', '/static/img/products/cocoa-coconut-walnut-cookies.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='cocoa-coconut-walnut-cookies'), '1 cookie', 3.00, 0), ((SELECT id FROM products WHERE slug='cocoa-coconut-walnut-cookies'), 'Pack of 8', 21.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'date-swirl-cookies', 'Date Swirl Cookies',
  'Tender, golden cookie dough made with gluten-free oat flour, rolled around our homemade date paste and baked into soft spirals with a gently caramelized edge.',
  'Simple, comforting, and naturally sweet in every bite.', '', '/static/img/products/date-swirl-cookies.jpg', NULL, 60, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='date-swirl-cookies'), '1 cookie', 2.50, 0), ((SELECT id FROM products WHERE slug='date-swirl-cookies'), 'Pack of 10', 22.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='cookies'), 'peanut-butter-cookies', 'Peanut Butter Cookies',
  'Soft, thick cookies made with our homemade peanut butter, topped with a fluffy peanut cream and a generous drizzle of warm peanut butter.',
  'Pure comfort for every peanut butter lover.', 'Peanuts', '/static/img/products/peanut-butter-cookies.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='peanut-butter-cookies'), '1 cookie', 3.00, 0), ((SELECT id FROM products WHERE slug='peanut-butter-cookies'), 'Pack of 10', 26.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='brownies-bars'), 'banana-cacao-brownie', 'Banana Cacao Brownie',
  'Dense, fudgy brownies made with ripe banana, pure cacao, and dark chocolate chips, finished with fresh strawberries.',
  'All the chocolate you crave, sweetened by nature.', '', '/static/img/products/banana-cacao-brownie.jpg', NULL, 40, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='banana-cacao-brownie'), '1 brownie', 4.50, 0), ((SELECT id FROM products WHERE slug='banana-cacao-brownie'), 'Box of 4', 16.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='brownies-bars'), 'peanut-caramel-bar', 'Peanut Caramel Bar',
  'A soft nougat base, a thick layer of golden caramel made with coconut sugar, and a mountain of roasted peanuts finished with a drizzle of cocoa butter chocolate.',
  'Everything you love about the classic candy bar, made the natural way.', 'Peanuts', '/static/img/products/peanut-caramel-bar.jpg', NULL, 30, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='peanut-caramel-bar'), '1 bar', 5.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='brownies-bars'), 'almond-chocolate-bar', 'Almond Chocolate Bar',
  'Rich, creamy chocolate made with pure cocoa butter and coconut sugar, generously topped with crushed almonds.',
  'A classic chocolate bar, reimagined the natural way.', 'Tree nuts (almond)', '/static/img/products/chocolate-bars.jpg', NULL, 30, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='almond-chocolate-bar'), '1 bar', 9.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='brownies-bars'), 'walnut-chocolate-bar', 'Walnut Chocolate Bar',
  'Rich, creamy chocolate made with pure cocoa butter and coconut sugar, generously topped with crushed walnuts.',
  'A classic chocolate bar, reimagined the natural way.', 'Tree nuts (walnut)', '/static/img/products/chocolate-bars.jpg', NULL, 30, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='walnut-chocolate-bar'), '1 bar', 9.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='brownies-bars'), 'pistachio-chocolate-bar', 'Pistachio Chocolate Bar',
  'Rich, creamy chocolate made with pure cocoa butter and coconut sugar, generously topped with crushed pistachios.',
  'A classic chocolate bar, reimagined the natural way.', 'Tree nuts (pistachio)', '/static/img/products/chocolate-bars.jpg', NULL, 30, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-chocolate-bar'), '1 bar', 10.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='brownies-bars'), 'pistachio-kataifi-bar', 'Pistachio Kataifi Chocolate Bar',
  'A thick shell of cocoa butter chocolate filled with a crunchy center of toasted kataifi and our homemade pistachio cream, finished with a chocolate drizzle and crushed pistachios.',
  'The viral favorite, made the Velouré way.', 'Tree nuts (pistachio)', '/static/img/products/pistachio-kataifi-bar.jpg', NULL, 30, FALSE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-kataifi-bar'), '1 bar', 12.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'energy-balls-mix', 'Energy Balls Mix',
  'A curated selection of our hand-rolled energy balls in assorted flavors, made with our homemade artisanal nut butters and dipped in cocoa butter chocolate.',
  'A little box of natural energy, perfect for sharing.', 'Tree nuts, peanuts, sesame, coconut', '/static/img/products/energy-balls.jpg', NULL, 25, FALSE, TRUE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='energy-balls-mix'), 'Box of 6', 14.00, 0), ((SELECT id FROM products WHERE slug='energy-balls-mix'), 'Box of 12', 26.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'coffee-energy-ball', 'Coffee Energy Ball',
  'A hand-rolled energy ball with a bold coffee center, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (cashew)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, TRUE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='coffee-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'almond-energy-ball', 'Almond Energy Ball',
  'A hand-rolled energy ball with roasted almonds and our homemade almond butter, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (almond)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='almond-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'pistachio-energy-ball', 'Pistachio Energy Ball',
  'A hand-rolled energy ball with crushed pistachios and our homemade pistachio butter, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (pistachio)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'coconut-energy-ball', 'Coconut Energy Ball',
  'A hand-rolled energy ball with toasted coconut and our homemade coconut butter, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Coconut', '/static/img/products/energy-balls.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='coconut-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'fig-energy-ball', 'Fig Energy Ball',
  'A hand-rolled energy ball with soft figs and toasted almonds, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (almond)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='fig-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'dark-cacao-energy-ball', 'Dark Cacao Energy Ball',
  'A hand-rolled energy ball with deep dark cacao, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (cashew)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='dark-cacao-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'hazelnut-energy-ball', 'Hazelnut Energy Ball',
  'A hand-rolled energy ball with roasted hazelnuts and our homemade hazelnut butter, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (hazelnut)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='hazelnut-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'peanut-energy-ball', 'Peanut Energy Ball',
  'A hand-rolled energy ball with roasted peanuts and our homemade peanut butter, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Peanuts', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='peanut-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'orange-hazelnut-energy-ball', 'Orange & Hazelnut Energy Ball',
  'A hand-rolled energy ball with toasted hazelnuts and bright orange zest, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (hazelnut)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='orange-hazelnut-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'raspberry-energy-ball', 'Raspberry Energy Ball',
  'A hand-rolled energy ball with a tangy heart of our homemade raspberry jam, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (cashew)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='raspberry-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'tahini-energy-ball', 'Tahini Energy Ball',
  'A hand-rolled energy ball with our homemade tahini and toasted sesame, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Sesame', '/static/img/products/energy-balls.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='tahini-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'matcha-energy-ball', 'Matcha Energy Ball',
  'A hand-rolled energy ball with earthy matcha, finished in cocoa butter chocolate.',
  'A little boost of natural energy for any moment of the day.', 'Tree nuts (cashew)', '/static/img/products/energy-balls.jpg', NULL, 80, FALSE, TRUE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='matcha-energy-ball'), '1 piece', 2.50, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'brownie-bites', 'Brownie Bites',
  'Soft, fudgy little bites with the deep flavor of a brownie, made with dates, cacao, and walnuts, and studded with dark chocolate chips.',
  'One bite, and you''ll understand why the box never lasts.', 'Tree nuts (walnut)', '/static/img/products/brownie-bites.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='brownie-bites'), '1 piece', 2.50, 0), ((SELECT id FROM products WHERE slug='brownie-bites'), 'Box of 6', 14.00, 1), ((SELECT id FROM products WHERE slug='brownie-bites'), 'Box of 12', 26.00, 2);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'coconut-raspberry-snowballs', 'Coconut Raspberry Snowballs',
  'Inside every bite you''ll find coconut, creamy coconut milk, crunchy almonds, and a hidden raspberry heart.',
  'Soft, snowy, and impossible to eat just one.', 'Tree nuts (almond), coconut', '/static/img/products/coconut-raspberry-snowballs.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='coconut-raspberry-snowballs'), '1 piece', 2.75, 0), ((SELECT id FROM products WHERE slug='coconut-raspberry-snowballs'), 'Box of 6', 15.00, 1), ((SELECT id FROM products WHERE slug='coconut-raspberry-snowballs'), 'Box of 12', 28.00, 2);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'pistachio-caramel-truffles', 'Pistachio Caramel Truffles',
  'A soft, chewy caramel center, dipped in cocoa butter chocolate and rolled in crushed pistachios.',
  'All the flavor of your favorite candy bar, made the natural way.', 'Tree nuts (pistachio)', '/static/img/products/pistachio-caramel-truffles.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-caramel-truffles'), '1 piece', 3.00, 0), ((SELECT id FROM products WHERE slug='pistachio-caramel-truffles'), 'Box of 6', 17.00, 1), ((SELECT id FROM products WHERE slug='pistachio-caramel-truffles'), 'Box of 12', 32.00, 2);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'hazelnut-crunch-truffles', 'Hazelnut Crunch Truffles',
  'A creamy hazelnut and chocolate center with a crunchy heart, coated in cocoa butter chocolate and finished with toasted hazelnuts and a pinch of sea salt.',
  'A little golden moment of pure indulgence.', 'Tree nuts (hazelnut)', '/static/img/products/hazelnut-crunch-truffles.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='hazelnut-crunch-truffles'), '1 piece', 2.75, 0), ((SELECT id FROM products WHERE slug='hazelnut-crunch-truffles'), 'Box of 8', 20.00, 1), ((SELECT id FROM products WHERE slug='hazelnut-crunch-truffles'), 'Box of 16', 38.00, 2);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'almond-butter-cup', 'Almond Butter Cup',
  'A thick shell of dark chocolate made with pure cocoa butter, filled with our homemade artisanal almond butter and crowned with a single whole almond.',
  'Smooth, snappy, and impossible to have just one.', 'Tree nuts (almond)', '/static/img/products/almond-butter-cup.jpg', NULL, 60, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='almond-butter-cup'), '1 piece', 3.50, 0), ((SELECT id FROM products WHERE slug='almond-butter-cup'), 'Box of 6', 19.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='truffles-energy-balls'), 'chocolate-mousse-cups', 'Chocolate Mousse Cups',
  'A silky chocolate mousse made with chickpeas, dates, and our homemade tahini, piped into stars and finished with crunchy roasted hazelnuts.',
  'Rich and indulgent, with a surprisingly wholesome secret.', 'Sesame, tree nuts (hazelnut)', '/static/img/products/chocolate-mousse-cups.jpg', NULL, 30, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='chocolate-mousse-cups'), '1 cup', 6.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'stuffed-dates-mix', 'Stuffed Dates Mix',
  'Soft, caramel-like dates filled with our homemade artisanal nut and coconut butters, dipped in cocoa butter chocolate, and crowned with pistachios, cashews, almonds, or dried berries.',
  'Little bites of indulgence, made to be gifted and shared.', 'Tree nuts, peanuts, sesame, coconut', '/static/img/products/stuffed-dates.jpg', '/static/img/products/stuffed-dates-2.jpg', 25, FALSE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='stuffed-dates-mix'), 'Box of 6', 15.00, 0), ((SELECT id FROM products WHERE slug='stuffed-dates-mix'), 'Box of 12', 28.00, 1);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'pistachio-stuffed-date', 'Pistachio Stuffed Date',
  'A soft, caramel-like date filled with our homemade pistachio butter, topped with crushed pistachios, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Tree nuts (pistachio)', '/static/img/products/stuffed-dates.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='pistachio-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'almond-stuffed-date', 'Almond Stuffed Date',
  'A soft, caramel-like date filled with our homemade almond butter, crowned with a whole almond, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Tree nuts (almond)', '/static/img/products/stuffed-dates.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='almond-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'cashew-stuffed-date', 'Cashew Stuffed Date',
  'A soft, caramel-like date filled with our homemade cashew butter, crowned with a whole cashew, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Tree nuts (cashew)', '/static/img/products/stuffed-dates.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='cashew-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'hazelnut-stuffed-date', 'Hazelnut Stuffed Date',
  'A soft, caramel-like date filled with our homemade hazelnut butter and toasted hazelnuts, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Tree nuts (hazelnut)', '/static/img/products/stuffed-dates.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='hazelnut-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'peanut-crunch-stuffed-date', 'Peanut Crunch Stuffed Date',
  'A soft, caramel-like date filled with our homemade peanut butter and crunchy roasted peanuts, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Peanuts', '/static/img/products/stuffed-dates.jpg', NULL, 80, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='peanut-crunch-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'coconut-stuffed-date', 'Coconut Stuffed Date',
  'A soft, caramel-like date filled with our homemade coconut butter, rolled in toasted coconut, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Coconut', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='coconut-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'raspberry-stuffed-date', 'Raspberry Stuffed Date',
  'A soft, caramel-like date filled with our homemade coconut butter and raspberry paste, topped with a fresh raspberry, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Coconut', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='raspberry-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'strawberry-stuffed-date', 'Strawberry Stuffed Date',
  'A soft, caramel-like date filled with our homemade coconut butter and strawberry paste, topped with dried strawberry, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Coconut', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='strawberry-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'mango-stuffed-date', 'Mango Stuffed Date',
  'A soft, caramel-like date filled with our homemade coconut butter and mango paste, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Coconut', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='mango-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'orange-stuffed-date', 'Orange Stuffed Date',
  'A soft, caramel-like date filled with our homemade coconut butter and candied orange, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Coconut', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='orange-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'tahini-stuffed-date', 'Tahini Stuffed Date',
  'A soft, caramel-like date filled with our homemade tahini and toasted sesame, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Sesame', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='tahini-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='stuffed-dates'), 'salted-caramel-stuffed-date', 'Salted Caramel Stuffed Date',
  'A soft, caramel-like date filled with a soft date caramel with a pinch of sea salt, dipped in cocoa butter chocolate.',
  'A little bite of indulgence.', 'Coconut', '/static/img/products/stuffed-dates.jpg', NULL, 80, TRUE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='salted-caramel-stuffed-date'), '1 piece', 2.75, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='gift-boxes'), 'veloure-signature-box', 'Velouré Signature Box',
  'A curated selection of our truffles, energy balls, stuffed dates, and cookies, presented in our signature Velouré box and tied with a satin gold ribbon.',
  'Give something sweet, the kind that loves them back.', 'Tree nuts, peanuts, sesame, coconut', '/static/img/products/veloure-signature-box.jpg', NULL, 10, FALSE, FALSE, FALSE, TRUE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='veloure-signature-box'), 'Signature box', 42.00, 0);

INSERT INTO products (category_id, slug, name, description, tagline, allergens, image_url, image2_url, stock, is_nut_free, contains_caffeine, is_seasonal, is_best_seller) VALUES ((SELECT id FROM categories WHERE slug='gift-boxes'), 'truffle-date-gift-box', 'Truffle & Date Gift Box',
  'A curated collection of our stuffed dates, dipped in cocoa butter chocolate and crowned with pistachios, almonds, cashews, fresh berries, and touches of gold, presented in our signature Velouré box with a satin ribbon.',
  'The gift that says everything, beautifully.', 'Tree nuts (pistachio, almond, cashew), peanuts', '/static/img/products/truffle-date-gift-box.jpg', NULL, 10, FALSE, FALSE, FALSE, FALSE);
INSERT INTO product_variants (product_id, label, price, sort_order) VALUES ((SELECT id FROM products WHERE slug='truffle-date-gift-box'), 'Box of 15', 39.00, 0);

-- ---------- A SEASONAL COUPON FOR MEMBERS ----------
INSERT INTO coupons (code, percent_off, description) VALUES ('AUTUMN15', 15, 'Autumn at Velouré: 15% off for members');
