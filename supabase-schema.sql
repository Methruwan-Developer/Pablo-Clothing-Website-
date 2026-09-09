create extension if not exists "pgcrypto";

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  price numeric(12,2) not null check (price >= 0),
  image text not null,
  description text not null default '',
  barcode text unique,
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  size_stock jsonb not null default '{"S": 0, "M": 0, "L": 0, "XL": 0}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.products add column if not exists barcode text;
alter table public.products add column if not exists stock_quantity integer not null default 0;
alter table public.products add column if not exists size_stock jsonb not null default '{"S": 0, "M": 0, "L": 0, "XL": 0}'::jsonb;
update public.products
set size_stock = jsonb_build_object('S', 0, 'M', stock_quantity, 'L', 0, 'XL', 0)
where size_stock = '{"S": 0, "M": 0, "L": 0, "XL": 0}'::jsonb and stock_quantity > 0;
create unique index if not exists products_barcode_idx on public.products(barcode) where barcode is not null;
update public.products set category = 'arm-cut' where category = 'skinny';
update public.products set active = true where stock_quantity <= 0;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  customer_name text not null,
  phone text not null,
  address text not null,
  bank_ref text not null,
  receipt_path text,
  total numeric(12,2) not null check (total >= 0),
  status text not null default 'Pending' check (status in ('Pending', 'Completed')),
  created_at timestamptz not null default now()
);

alter table public.orders add column if not exists receipt_path text;

create sequence if not exists public.profile_public_id_seq start with 1;

create table if not exists public.admin_users (
  email text primary key,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

insert into public.admin_users (email)
values ('pabloclothingprivatelimited@gmail.com')
on conflict (email) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  public_id text unique not null default ('PAB-' || lpad(nextval('public.profile_public_id_seq')::text, 7, '0')),
  name text not null default '',
  email text not null default '',
  phone text not null default '',
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists public_id text;
update public.profiles
set public_id = 'PAB-' || lpad(nextval('public.profile_public_id_seq')::text, 7, '0')
where public_id is null;
alter table public.profiles alter column public_id set default ('PAB-' || lpad(nextval('public.profile_public_id_seq')::text, 7, '0'));
alter table public.profiles alter column public_id set not null;
create unique index if not exists profiles_public_id_idx on public.profiles(public_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, phone)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''), new.email, coalesce(new.raw_user_meta_data->>'phone', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  name text not null,
  size text not null,
  quantity integer not null check (quantity > 0),
  price numeric(12,2) not null check (price >= 0)
);

alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.profiles enable row level security;
alter table public.admin_users enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admin_users
    where lower(email) = lower(coalesce(auth.jwt()->>'email', ''))
  );
$$;

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('payment-slips', 'payment-slips', false)
on conflict (id) do update set public = false;

drop policy if exists "Customers upload payment slips" on storage.objects;
create policy "Customers upload payment slips" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'payment-slips');

drop policy if exists "Admins view payment slips" on storage.objects;
create policy "Admins view payment slips" on storage.objects
  for select using (bucket_id = 'payment-slips' and public.is_admin());

drop policy if exists "Anyone can view product images" on storage.objects;
create policy "Anyone can view product images" on storage.objects
  for select using (bucket_id = 'product-images');

drop policy if exists "Admins upload product images" on storage.objects;
create policy "Admins upload product images" on storage.objects
  for insert with check (bucket_id = 'product-images' and public.is_admin());

drop policy if exists "Admins update product images" on storage.objects;
create policy "Admins update product images" on storage.objects
  for update using (bucket_id = 'product-images' and public.is_admin()) with check (bucket_id = 'product-images' and public.is_admin());

drop policy if exists "Admins delete product images" on storage.objects;
create policy "Admins delete product images" on storage.objects
  for delete using (bucket_id = 'product-images' and public.is_admin());

drop policy if exists "Anyone can view active products" on public.products;
create policy "Anyone can view active products" on public.products
  for select using (active = true or public.is_admin());

drop policy if exists "Authenticated admins manage products" on public.products;
create policy "Authenticated admins manage products" on public.products
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Customers view their orders" on public.orders;
create policy "Customers view their orders" on public.orders
  for select using (auth.uid() = user_id or public.is_admin());

drop policy if exists "Customers create orders" on public.orders;
drop policy if exists "Guests and customers create orders" on public.orders;
create policy "Guests and customers create orders" on public.orders
  for insert to anon, authenticated
  with check ((user_id is null) or (auth.uid() is not null and auth.uid() = user_id));

drop policy if exists "Authenticated admins update orders" on public.orders;
create policy "Authenticated admins update orders" on public.orders
  for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Authenticated admins delete orders" on public.orders;
create policy "Authenticated admins delete orders" on public.orders
  for delete using (public.is_admin());

drop policy if exists "Customers view their order items" on public.order_items;
create policy "Customers view their order items" on public.order_items
  for select using (exists (select 1 from public.orders where orders.id = order_id and (orders.user_id = auth.uid() or public.is_admin())));

create or replace function public.can_insert_order_item(p_order_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.orders
    where id = p_order_id
      and (user_id is null or (auth.uid() is not null and user_id = auth.uid()))
  );
$$;

grant execute on function public.can_insert_order_item(uuid) to anon, authenticated;

drop policy if exists "Customers create order items" on public.order_items;
drop policy if exists "Guests and customers create order items" on public.order_items;
create policy "Guests and customers create order items" on public.order_items
  for insert to anon, authenticated
  with check (public.can_insert_order_item(order_id));

drop policy if exists "Authenticated admins delete order items" on public.order_items;
create policy "Authenticated admins delete order items" on public.order_items
  for delete using (public.is_admin());

drop policy if exists "Authenticated admins view profiles" on public.profiles;
create policy "Authenticated admins view profiles" on public.profiles
  for select using (public.is_admin() or auth.uid() = id);

drop policy if exists "Authenticated admins delete profiles" on public.profiles;
create policy "Authenticated admins delete profiles" on public.profiles
  for delete using (public.is_admin());

drop policy if exists "Admins view admin allowlist" on public.admin_users;
create policy "Admins view admin allowlist" on public.admin_users
  for select using (public.is_admin());

drop policy if exists "Admins add admin allowlist entries" on public.admin_users;
create policy "Admins add admin allowlist entries" on public.admin_users
  for insert with check (public.is_admin());

create index if not exists orders_user_id_idx on public.orders(user_id);
create index if not exists orders_created_at_idx on public.orders(created_at desc);
create index if not exists order_items_order_id_idx on public.order_items(order_id);

create or replace function public.decrement_product_stock(
  p_product_id uuid,
  p_size text,
  p_quantity integer,
  p_order_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_stock integer;
  next_stock jsonb;
begin
  if p_size not in ('S', 'M', 'L', 'XL') or p_quantity <= 0 then
    raise exception 'Invalid size or quantity';
  end if;

  if not exists (
    select 1 from public.orders
    where id = p_order_id
      and (user_id is null or (auth.uid() is not null and user_id = auth.uid()))
  ) then
    raise exception 'Order is not available for this user';
  end if;

  select coalesce((size_stock ->> p_size)::integer, 0)
    into current_stock
    from public.products
   where id = p_product_id
   for update;

  if current_stock is null or current_stock < p_quantity then
    raise exception 'Insufficient stock for size %', p_size;
  end if;

  next_stock = jsonb_set(
    coalesce((select size_stock from public.products where id = p_product_id), '{}'::jsonb),
    array[p_size],
    to_jsonb(current_stock - p_quantity),
    true
  );

  update public.products
     set size_stock = next_stock,
       stock_quantity = greatest(stock_quantity - p_quantity, 0)
   where id = p_product_id;
end;
$$;

grant execute on function public.decrement_product_stock(uuid, text, integer, uuid) to anon, authenticated;

-- 1. Add barcode column to products table
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS barcode TEXT;

CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);

-- 2. Create Storage Bucket for product images if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Storage Policies for product-images bucket
DROP POLICY IF EXISTS "Public Read Product Images" ON storage.objects;
CREATE POLICY "Public Read Product Images" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Authenticated Upload Product Images" ON storage.objects;
CREATE POLICY "Authenticated Upload Product Images" 
ON storage.objects FOR INSERT 
WITH CHECK (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Authenticated Update Product Images" ON storage.objects;
CREATE POLICY "Authenticated Update Product Images" 
ON storage.objects FOR UPDATE 
WITH CHECK (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Authenticated Delete Product Images" ON storage.objects;
CREATE POLICY "Authenticated Delete Product Images" 
ON storage.objects FOR DELETE 
USING (bucket_id = 'product-images');

-- 4. Ensure profiles RLS allows reading count for metric display
DROP POLICY IF EXISTS "Allow authenticated read profiles count" ON profiles;
CREATE POLICY "Allow authenticated read profiles count" 
ON profiles FOR SELECT 
TO authenticated 
USING (true);