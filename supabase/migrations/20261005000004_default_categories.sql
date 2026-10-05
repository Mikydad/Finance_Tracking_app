-- Built-in categories from the PRD (Section 12). user_id is null, so every
-- signed-in user can read them; key is what the categorizer and AI return.

with parents (key, name, icon, kind, sort_order) as (
  values
    ('food',          'Food',          'restaurant',     'expense', 10),
    ('transport',     'Transport',     'directions_car', 'expense', 20),
    ('shopping',      'Shopping',      'shopping_bag',   'expense', 30),
    ('bills',         'Bills',         'receipt',        'expense', 40),
    ('entertainment', 'Entertainment', 'movie',          'expense', 50),
    ('health',        'Health',        'favorite',       'expense', 60),
    ('education',     'Education',     'school',         'expense', 70),
    ('family',        'Family',        'family',         'expense', 80),
    ('subscriptions', 'Subscriptions', 'autorenew',      'expense', 90),
    ('income',        'Income',        'payments',       'income',  100),
    ('transfer',      'Transfer',      'swap_horiz',     'both',    110),
    ('other',         'Other',         'more_horiz',     'both',    120)
)
insert into public.categories (key, name, icon, kind, sort_order)
select key, name, icon, kind, sort_order from parents;

with children (parent_key, key, name, sort_order) as (
  values
    ('food',      'food.restaurants',          'Restaurants',      1),
    ('food',      'food.groceries',            'Groceries',        2),
    ('food',      'food.coffee',               'Coffee',           3),
    ('transport', 'transport.taxi',            'Taxi',             1),
    ('transport', 'transport.fuel',            'Fuel',             2),
    ('transport', 'transport.public',          'Public transport', 3),
    ('bills',     'bills.internet',            'Internet',         1),
    ('bills',     'bills.phone',               'Phone',            2),
    ('bills',     'bills.electricity',         'Electricity',      3)
)
insert into public.categories (parent_id, key, name, kind, sort_order)
select p.id, c.key, c.name, 'expense', c.sort_order
from children c
join public.categories p on p.key = c.parent_key and p.user_id is null;
