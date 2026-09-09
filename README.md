# Pablo Clothing

## Supabase setup

1. Create a Supabase project.
2. Open the SQL editor and run `supabase-schema.sql`.
3. Copy the project URL and anon key into `supabase-config.js`.
4. Create the first admin user through the storefront registration form.
5. Sign in with `Pabloclothingprivatelimited@gmail.com` to open `admin.html`.
6. Use **Add Admin** in the panel to approve another email. That person must then register/sign in with the same email.

The pages no longer seed demo products, orders, or browser-stored passwords. Customer profiles receive stable IDs such as `PAB-0000001`. The storefront loads only active, in-stock products from Supabase, and checkout writes an order plus its line items to the database.

Product images are uploaded through the admin product form into the public Supabase Storage bucket `product-images`. The bucket and its admin-only upload policies are created by `supabase-schema.sql`.

## Security note

Because this is a static browser application, users can inspect the HTML and JavaScript files in browser developer tools. The Supabase publishable key is intended to be public; database protection comes from the RLS policies in `supabase-schema.sql`, and admin access is checked by the `is_admin()` function. Never place a Supabase service-role key, database password, or other private secret in these frontend files.

Production responses also include security headers configured in `vercel.json`.